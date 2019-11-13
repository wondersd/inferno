# frozen_string_literal: true

module Inferno
  module Sequence
    class USCore310ImplantableDeviceSequence < SequenceBase
      title 'Implantable Device Tests'

      description 'Verify that Device resources on the FHIR server follow the US Core Implementation Guide'

      test_id_prefix 'USCID'

      requires :token, :patient_id
      conformance_supports :Device

      def validate_resource_item(resource, property, value)
        case property

        when 'patient'
          value_found = can_resolve_path(resource, 'patient.reference') { |reference| [value, 'Patient/' + value].include? reference }
          assert value_found, 'patient on resource does not match patient requested'

        when 'type'
          value_found = can_resolve_path(resource, 'type.coding.code') { |value_in_resource| value_in_resource == value }
          assert value_found, 'type on resource does not match type requested'

        end
      end

      details %(
        The #{title} Sequence tests `#{title.gsub(/\s+/, '')}` resources associated with the provided patient.
      )

      @resources_found = false

      test :unauthorized_search do
        metadata do
          id '01'
          name 'Server rejects Device search without authorization'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html#behavior'
          description %(
            A server SHALL reject any unauthorized requests by returning an HTTP 401 unauthorized response code.
          )
          versions :r4
        end

        skip_if_not_supported(:Device, [:search])

        @client.set_no_auth
        omit 'Do not test if no bearer token set' if @instance.token.blank?

        search_params = {
          'patient': @instance.patient_id
        }

        reply = get_resource_by_params(versioned_resource_class('Device'), search_params)
        @client.set_bearer_token(@instance.token)
        assert_response_unauthorized reply
      end

      test 'Server returns expected results from Device search by patient' do
        metadata do
          id '02'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          description %(

            A server SHALL be able to support searching by patient on the Device resource

          )
          versions :r4
        end

        search_params = {
          'patient': @instance.patient_id
        }

        reply = get_resource_by_params(versioned_resource_class('Device'), search_params)
        assert_response_ok(reply)
        assert_bundle_response(reply)

        resource_count = reply&.resource&.entry&.length || 0
        @resources_found = true if resource_count.positive?

        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found

        @device = reply&.resource&.entry&.first&.resource
        @device_ary = fetch_all_bundled_resources(reply&.resource)
        save_resource_ids_in_bundle(versioned_resource_class('Device'), reply)
        save_delayed_sequence_references(@device_ary)
        validate_search_reply(versioned_resource_class('Device'), reply, search_params)
      end

      test 'Server returns expected results from Device search by patient+type' do
        metadata do
          id '03'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          optional
          description %(

            A server SHOULD be able to support searching by patient+type on the Device resource

          )
          versions :r4
        end

        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found
        assert !@device.nil?, 'Expected valid Device resource to be present'

        search_params = {
          'patient': @instance.patient_id,
          'type': get_value_for_search_param(resolve_element_from_path(@device_ary, 'type'))
        }
        search_params.each { |param, value| skip "Could not resolve #{param} in given resource" if value.nil? }

        reply = get_resource_by_params(versioned_resource_class('Device'), search_params)
        validate_search_reply(versioned_resource_class('Device'), reply, search_params)
        assert_response_ok(reply)
      end

      test :read_interaction do
        metadata do
          id '04'
          name 'Device read interaction supported'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          description %(
            All servers SHALL make available read interactions on Device
          )
          versions :r4
        end

        skip_if_not_supported(:Device, [:read])
        skip 'No Device resources could be found for this patient. Please use patients with more information.' unless @resources_found

        validate_read_reply(@device, versioned_resource_class('Device'))
      end

      test :vread_interaction do
        metadata do
          id '05'
          name 'Device vread interaction supported'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          description %(
            All servers SHOULD make available vread interactions on Device
          )
          versions :r4
        end

        skip_if_not_supported(:Device, [:vread])
        skip 'No Device resources could be found for this patient. Please use patients with more information.' unless @resources_found

        validate_vread_reply(@device, versioned_resource_class('Device'))
      end

      test :history_interaction do
        metadata do
          id '06'
          name 'Device history interaction supported'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          description %(
            All servers SHOULD make available history interactions on Device
          )
          versions :r4
        end

        skip_if_not_supported(:Device, [:history])
        skip 'No Device resources could be found for this patient. Please use patients with more information.' unless @resources_found

        validate_history_reply(@device, versioned_resource_class('Device'))
      end

      test 'Server returns the appropriate resources from the following _revincludes: Provenance:target' do
        metadata do
          id '07'
          link 'https://www.hl7.org/fhir/search.html#revinclude'
          description %(
            A Server SHALL be capable of supporting the following _revincludes: Provenance:target
          )
          versions :r4
        end

        search_params = {
          'patient': @instance.patient_id
        }

        search_params['_revinclude'] = 'Provenance:target'
        reply = get_resource_by_params(versioned_resource_class('Device'), search_params)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        provenance_results = reply&.resource&.entry&.map(&:resource)&.any? { |resource| resource.resourceType == 'Provenance' }
        assert provenance_results, 'No Provenance resources were returned from this search'
      end

      test 'Device resources associated with Patient conform to US Core R4 profiles' do
        metadata do
          id '08'
          link 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-implantable-device'
          description %(

            This test checks if the resources returned from prior searches conform to the US Core profiles.
            This includes checking for missing data elements and valueset verification.
          )
          versions :r4
        end

        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found
        test_resources_against_profile('Device')
      end

      test 'At least one of every must support element is provided in any Device for this patient.' do
        metadata do
          id '09'
          link 'http://www.hl7.org/fhir/us/core/general-guidance.html#must-support'
          description %(

            US Core Responders SHALL be capable of populating all data elements as part of the query results as specified by the US Core Server Capability Statement.
            This will look through all Device resources returned from prior searches too see if any of them provide the following must support elements:

            Device.udiCarrier

            Device.udiCarrier.deviceIdentifier

            Device.udiCarrier.carrierAIDC

            Device.udiCarrier.carrierHRF

            Device.distinctIdentifier

            Device.manufactureDate

            Device.expirationDate

            Device.lotNumber

            Device.serialNumber

            Device.type

            Device.patient

          )
          versions :r4
        end

        skip 'No resources appear to be available for this patient. Please use patients with more information' unless @device_ary&.any?
        must_support_confirmed = {}
        must_support_elements = [
          'Device.udiCarrier',
          'Device.udiCarrier.deviceIdentifier',
          'Device.udiCarrier.carrierAIDC',
          'Device.udiCarrier.carrierHRF',
          'Device.distinctIdentifier',
          'Device.manufactureDate',
          'Device.expirationDate',
          'Device.lotNumber',
          'Device.serialNumber',
          'Device.type',
          'Device.patient'
        ]
        must_support_elements.each do |path|
          @device_ary&.each do |resource|
            truncated_path = path.gsub('Device.', '')
            must_support_confirmed[path] = true if can_resolve_path(resource, truncated_path)
            break if must_support_confirmed[path]
          end
          resource_count = @device_ary.length

          skip "Could not find #{path} in any of the #{resource_count} provided Device resource(s)" unless must_support_confirmed[path]
        end
        @instance.save!
      end

      test 'All references can be resolved' do
        metadata do
          id '10'
          link 'https://www.hl7.org/fhir/DSTU2/references.html'
          description %(
            This test checks if references found in resources from prior searches can be resolved.
          )
          versions :r4
        end

        skip_if_not_supported(:Device, [:search, :read])
        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found

        validate_reference_resolutions(@device)
      end
    end
  end
end

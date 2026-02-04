# frozen_string_literal: true

require_relative '../../../step/company_pending_par'

module Engine
  module Game
    module G1832
      module Step
        # Subclasses Engine base directly (not G1870) to avoid auto-closing P7
        # after par. P7 (West Virginia Central & Pittsburgh) closes naturally
        # via event_close_companies! at the first 5-train, or when CoG
        # purchases its first train.
        class CompanyPendingPar < Engine::Step::CompanyPendingPar
        end
      end
    end
  end
end

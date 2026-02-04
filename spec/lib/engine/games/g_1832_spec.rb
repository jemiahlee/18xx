# frozen_string_literal: true

require './spec/spec_helper'

module Engine
  describe Game::G1832 do
    let(:players) { %w[Alice Bob Carol] }

    subject(:game) { Game::G1832::Game.new(players) }

    context 'on init with 3 players' do
      it 'starts with correct bank cash' do
        expect(game.bank.cash).to eq(12_000 - (3 * 700))
      end

      it 'starts with correct player cash' do
        expect(game.players.map(&:cash)).to all(eq(700))
      end

      it 'starts in the initial auction round' do
        expect(game.round).to be_a(Round::Auction)
      end

      it 'has the correct number of corporations' do
        # 10 major + 5 systems
        expect(game.corporations.count { |c| c.type == :major }).to eq(10)
        expect(game.corporations.count { |c| c.type == :system }).to eq(5)
      end

      it 'has 6 private companies available' do
        expect(game.companies.size).to eq(6)
      end

      it 'starts with 5 coal tokens' do
        expect(game.coal_token_counter).to eq(5)
      end

      it 'has FECR with an assign_hexes ability for Key West' do
        fecr = game.fec_corporation
        ability = game.abilities(fecr, :assign_hexes)
        expect(ability).not_to be_nil
        expect(ability.hexes).to include('N16')
      end

      it 'has boomtown hexes defined' do
        expect(Game::G1832::Game::BOOMTOWN_HEXES).not_to be_empty
      end
    end

    context 'with 2 players' do
      let(:players) { %w[Alice Bob] }

      subject(:game2p) { Game::G1832::Game.new(players) }

      it 'starts with correct 2-player cash' do
        expect(game2p.players.map(&:cash)).to all(eq(1050))
      end
    end

    context 'with southern_bank optional rule' do
      subject(:sb_game) { Game::G1832::Game.new(players, optional_rules: [:southern_bank]) }

      it 'uses southern bank starting cash' do
        expect(sb_game.players.map(&:cash)).to all(eq(800))
      end
    end
  end
end

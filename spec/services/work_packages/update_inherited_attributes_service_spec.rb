#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

require 'spec_helper'

describe WorkPackages::UpdateInheritedAttributesService, type: :model do
  let(:user) { FactoryGirl.create :user }
  let(:parent) { FactoryGirl.create :work_package, status: open_status }
  let(:estimated_hours) { [nil, nil, nil] }
  let(:done_ratios) { [0, 0, 0] }
  let(:statuses) { %i(open open open) }
  let(:open_status) { FactoryGirl.create :status }
  let(:closed_status) { FactoryGirl.create :closed_status }

  shared_examples 'attributes of parent having children' do
    let(:aggregate_done_ratio) { 0.0 }

    before do
      (statuses.size - 1).downto(0).each do |i|
        FactoryGirl.create :work_package,
                           parent: parent,
                           status: statuses[i] == :open ? open_status : closed_status,
                           estimated_hours: estimated_hours[i],
                           done_ratio: done_ratios[i]
      end

      parent.reload
    end

    it 'has the expected aggregate done ratio' do
      expect(subject.result.done_ratio).to eq aggregate_done_ratio
    end

    it 'has the expected estimated_hours' do
      expect(subject.result.estimated_hours).to eq aggregate_estimated_hours
    end

    it 'is a success' do
      expect(subject)
        .to be_success
    end
  end

  subject do
    described_class
      .new(user: user,
           work_package: parent)
      .call(%i(done_ratio estimated_hours))
  end

  context 'with no estimated hours and no progress' do
    it_behaves_like 'attributes of parent having children' do
      let(:statuses) { %i(open open open) }

      let(:aggregate_done_ratio) { 0 }
      let(:aggregate_estimated_hours) { nil }
    end
  end

  context 'with 1 out of 3 tasks having estimated hours and 2 out of 3 tasks done' do
    let(:statuses) { %i(open closed closed) }

    it_behaves_like 'attributes of parent having children' do
      let(:estimated_hours) { [0.0, 2.0, 0.0] }

      let(:aggregate_done_ratio) { 67 } # 66.67 rounded - previous wrong result: 133
      let(:aggregate_estimated_hours) { 2.0 }
    end

    context 'with mixed nil and 0 values for estimated hours' do
      it_behaves_like 'attributes of parent having children' do
        let(:estimated_hours) { [nil, 2.0, 0.0] }

        let(:aggregate_done_ratio) { 67 } # 66.67 rounded - previous wrong result: 100
        let(:aggregate_estimated_hours) { 2.0 }
      end
    end
  end

  context 'with no estimated hours and 1.5 of the tasks done' do
    it_behaves_like 'attributes of parent having children' do
      let(:done_ratios) { [0, 50, 100] }

      let(:aggregate_done_ratio) { 50 }
      let(:aggregate_estimated_hours) { nil }
    end
  end

  context 'with estimated hours being 1, 2 and 5' do
    let(:estimated_hours) { [1, 2, 5] }

    context 'with the last 2 tasks at 100% progress' do
      it_behaves_like 'attributes of parent having children' do
        let(:done_ratios) { [0, 100, 100] }

        # (2 + 5 = 7) / 8 estimated hours done
        let(:aggregate_done_ratio) { 88 } # 87.5 rounded
        let(:aggregate_estimated_hours) { estimated_hours.sum }
      end
    end

    context 'with the last 2 tasks closed (therefore at 100%)' do
      it_behaves_like 'attributes of parent having children' do
        let(:statuses) { %i(open closed closed) }

        # (2 + 5 = 7) / 8 estimated hours done
        let(:aggregate_done_ratio) { 88 } # 87.5 rounded
        let(:aggregate_estimated_hours) { estimated_hours.sum }
      end
    end

    context 'with mixed done ratios, statuses' do
      it_behaves_like 'attributes of parent having children' do
        let(:done_ratios) { [50, 75, 42] }
        let(:statuses) { %i(open open closed) }

        #  50%       75%        100% (42 ignored)
        # (0.5 * 1 + 0.75 * 2 + 1 * 5 [since closed] = 7)
        # (0.5 + 1.5 + 5 = 7) / 8 estimated hours done
        let(:aggregate_done_ratio) { 88 } # 87.5 rounded
        let(:aggregate_estimated_hours) { estimated_hours.sum }
      end
    end
  end

  context 'with everything playing together' do
    it_behaves_like 'attributes of parent having children' do
      let(:statuses) { %i(open open closed open) }
      let(:done_ratios) { [0, 0, 0, 50] }
      let(:estimated_hours) { [0.0, 3.0, nil, 7.0] }

      # (0 * 5 + 0 * 3 + 1 * 5 + 0.5 * 7 = 8.5) / 20 est. hours done
      let(:aggregate_done_ratio) { 43 } # 42.5 rounded
      let(:aggregate_estimated_hours) { 10.0 }
    end
  end
end

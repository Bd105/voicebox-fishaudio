import { ModelManagement } from '@/components/ServerSettings/ModelManagement';
import { FishAudioSection } from '@/components/ServerSettings/FishAudioSection';

export function ModelsTab() {
  return (
    <div className="h-full flex flex-col gap-6">
      <FishAudioSection />
      <ModelManagement />
    </div>
  );
}

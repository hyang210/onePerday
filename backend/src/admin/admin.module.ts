import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { AuthModule } from '../auth/auth.module';
import { AdminController } from './admin.controller';

@Module({
  imports: [PrismaModule, AuthModule],
  controllers: [AdminController],
})
export class AdminModule {}

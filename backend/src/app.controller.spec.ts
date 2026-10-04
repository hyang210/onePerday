import { Test, TestingModule } from '@nestjs/testing';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaService } from './prisma/prisma.service';
import { SupplementSearchService } from './supplement-search.service';
import { describe, beforeEach, it, expect } from '@jest/globals';

describe('AppController', () => {
  let appController: AppController;

  beforeEach(async () => {
    const app: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
      providers: [
        AppService,
        {
          provide: PrismaService,
          useValue: {}, // Mock PrismaService
        },
        {
          provide: SupplementSearchService,
          useValue: {}, // Mock SupplementSearchService
        }
      ],
    }).compile();

    appController = app.get<AppController>(AppController);
  });

  describe('root', () => {
    it('should return "OnePerDay!"', () => {
      expect(appController.getHello()).toBe('OnePerDay!');
    });
  });
});

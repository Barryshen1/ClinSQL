SELECT 1 FROM physionet-data.mimiciv_3_1_icu.icustays i
    WHERE i.hadm_id = uc.hadm_id
  );
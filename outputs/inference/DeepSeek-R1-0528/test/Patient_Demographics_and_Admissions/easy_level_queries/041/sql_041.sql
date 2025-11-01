WITH first_admission AS (
  SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN (
      SELECT 
          subject_id, 
          MIN(admittime) AS first_admittime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions`
      GROUP BY subject_id
  ) b ON a.subject_id = b.subject_id AND a.admittime = b.first_admittime
),
filtered_patients AS (
  SELECT 
      p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' 
      AND p.anchor_age BETWEEN 50 AND 60
),
anticoagulant_admissions AS (
  SELECT 
      fa.subject_id,
      fa.hadm_id
  FROM first_admission fa
  INNER JOIN filtered_patients fp 
      ON fa.subject_id = fp.subject_id
  WHERE EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
      WHERE rx.hadm_id = fa.hadm_id
        AND REGEXP_CONTAINS(LOWER(rx.drug), r'warfarin|heparin|enoxaparin|dalteparin|tinzaparin|fondaparinux|rivaroxaban|apixaban|edoxaban|dabigatran|argatroban|bivalirudin')
  )
),
first_icu_stay AS (
  SELECT 
      i.subject_id,
      i.hadm_id,
      i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN anticoagulant_admissions aa 
      ON i.hadm_id = aa.hadm_id
  WHERE i.intime = (
      SELECT MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i2
      WHERE i2.hadm_id = i.hadm_id
  )
)
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los_days
FROM first_icu_stay;
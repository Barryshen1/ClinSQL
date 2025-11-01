WITH cohort AS (
  SELECT p.subject_id, p.anchor_age, i.stay_id, i.intime, i.outtime, i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) >= 144
    AND i.hadm_id IN (
      SELECT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE (d.icd_version = 9 AND d.icd_code LIKE '250%')
         OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]'))
    )
    AND i.hadm_id IN (
      SELECT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE (d.icd_version = 9 AND d.icd_code LIKE '428%')
         OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
medication_classes AS (
  SELECT class, drug
  FROM UNNEST([
    STRUCT('antidiabetics' AS class, 'Metformin' AS drug),
    STRUCT('antidiabetics', 'Insulin'),
    STRUCT('antidiabetics', 'Glipizide'),
    STRUCT('antidiabetics', 'Glyburide'),
    STRUCT('antidiabetics', 'Pioglitazone'),
    STRUCT('antidiabetics', 'Rosiglitazone'),
    STRUCT('antidiabetics', 'Sitagliptin'),
    STRUCT('antidiabetics', 'Liraglutide'),
    STRUCT('antidiabetics', 'Exenatide'),
    STRUCT('antidiabetics', 'Dapagliflozin'),
    STRUCT('antidiabetics', 'Empagliflozin'),
    STRUCT('antidiabetics', 'Canagliflozin'),
    STRUCT('antidiabetics', 'Glimepiride'),
    STRUCT('antidiabetics', 'Alogliptin'),
    STRUCT('antidiabetics', 'Linagliptin'),
    STRUCT('antidiabetics', 'Tolbutamide'),
    STRUCT('antidiabetics', 'Chlorpropamide'),
    STRUCT('antidiabetics', 'Miglitol'),
    STRUCT('antidiabetics', 'Acarbose'),
    STRUCT('antidiabetics', 'Repaglinide'),
    STRUCT('antidiabetics', 'Nateglinide'),
    STRUCT('antidiabetics', 'Pramlintide'),
    STRUCT('antidiabetics', 'Saxagliptin'),
    STRUCT('antidiabetics', 'Vildagliptin'),
    STRUCT('antidiabetics', 'Tirzepatide'),
    STRUCT('beta-blockers', 'Metoprolol'),
    STRUCT('beta-blockers', 'Carvedilol'),
    STRUCT('beta-blockers', 'Atenolol'),
    STRUCT('beta-blockers', 'Propranolol'),
    STRUCT('beta-blockers', 'Labetalol'),
    STRUCT('beta-blockers', 'Nadolol'),
    STRUCT('beta-blockers', 'Timolol'),
    STRUCT('beta-blockers', 'Esmolol'),
    STRUCT('beta-blockers', 'Bisoprolol'),
    STRUCT('beta-blockers', 'Sotalol'),
    STRUCT('ACEi', 'Lisinopril'),
    STRUCT('ACEi', 'Enalapril'),
    STRUCT('ACEi', 'Ramipril'),
    STRUCT('ACEi', 'Captopril'),
    STRUCT('ACEi', 'Benazepril'),
    STRUCT('ACEi', 'Quinapril'),
    STRUCT('ACEi', 'Fosinopril'),
    STRUCT('ACEi', 'Moexipril'),
    STRUCT('ACEi', 'Perindopril'),
    STRUCT('ACEi', 'Trandolapril'),
    STRUCT('ARB', 'Losartan'),
    STRUCT('ARB', 'Valsartan'),
    STRUCT('ARB', 'Irbesartan'),
    STRUCT('ARB', 'Candesartan'),
    STRUCT('ARB', 'Telmisartan'),
    STRUCT('ARB', 'Olmesartan'),
    STRUCT('ARB', 'Azilsartan'),
    STRUCT('ARB', 'Eprosartan'),
    STRUCT('ARNI', 'Sacubitril/Valsartan'),
    STRUCT('loop diuretics', 'Furosemide'),
    STRUCT('loop diuretics', 'Bumetanide'),
    STRUCT('loop diuretics', 'Torsemide')
  ])
),
cohort_prescriptions AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.intime,
    c.outtime,
    mc.class,
    MAX(CASE WHEN p.starttime < (c.intime + INTERVAL '72' HOUR) AND p.stoptime > c.intime THEN 1 ELSE 0 END) AS first_window_active,
    MAX(CASE WHEN p.starttime < c.outtime AND p.stoptime > (c.outtime - INTERVAL '72' HOUR) THEN 1 ELSE 0 END) AS last_window_active
  FROM cohort c
  CROSS JOIN medication_classes mc
  LEFT JOIN (
    SELECT p.hadm_id, p.starttime, p.stoptime, mc.class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN medication_classes mc ON p.drug = mc.drug
  ) p ON c.hadm_id = p.hadm_id AND mc.class = p.class
  GROUP BY c.subject_id, c.stay_id, c.intime, c.outtime, mc.class
)
SELECT
  class,
  COUNT(*) AS total_patients,
  SUM(first_window_active) AS first_count,
  SUM(last_window_active) AS last_count,
  SUM(CASE WHEN first_window_active = 1 AND last_window_active = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN first_window_active = 0 AND last_window_active = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN first_window_active = 1 AND last_window_active = 0 THEN 1 ELSE 0 END) AS discontinued,
  ROUND(SUM(first_window_active) * 100.0 / COUNT(*), 2) AS first_percent,
  ROUND(SUM(last_window_active) * 100.0 / COUNT(*), 2) AS last_percent
FROM cohort_prescriptions
GROUP BY class;
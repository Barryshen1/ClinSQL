WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),
diabetes_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250.%')
     OR (icd_version = 10 AND (
       icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%'
     ))
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428.%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
filtered_cohort AS (
  SELECT c.*
  FROM cohort c
  WHERE c.hadm_id IN (SELECT hadm_id FROM diabetes_hadm)
    AND c.hadm_id IN (SELECT hadm_id FROM hf_hadm)
),
total_cohort AS (
  SELECT COUNT(*) AS total_patients
  FROM filtered_cohort
),
-- Antidiabetics
antidiabetic_first48 AS (
  SELECT COUNT(DISTINCT fc.hadm_id) AS n_first
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= fc.admittime
    AND pr.starttime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)
    AND (
      LOWER(pr.drug) LIKE '%insulin%'
      OR LOWER(pr.drug) LIKE '%metformin%'
      OR LOWER(pr.drug) LIKE '%glipizide%'
      OR LOWER(pr.drug) LIKE '%glyburide%'
      OR LOWER(pr.drug) LIKE '%glimepiride%'
      OR LOWER(pr.drug) LIKE '%pioglitazone%'
      OR LOWER(pr.drug) LIKE '%sitagliptin%'
      OR LOWER(pr.drug) LIKE '%linagliptin%'
      OR LOWER(pr.drug) LIKE '%saxagliptin%'
      OR LOWER(pr.drug) LIKE '%exenatide%'
      OR LOWER(pr.drug) LIKE '%liraglutide%'
      OR LOWER(pr.drug) LIKE '%dulaglutide%'
      OR LOWER(pr.drug) LIKE '%semaglutide%'
      OR LOWER(pr.drug) LIKE '%canagliflozin%'
      OR LOWER(pr.drug) LIKE '%dapagliflozin%'
      OR LOWER(pr.drug) LIKE '%empagliflozin%'
      OR LOWER(pr.drug) LIKE '%ertugliflozin%'
    )
),
antidiabetic_last12 AS (
  SELECT COUNT(DISTINCT fc.hadm_id) AS n_last
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= TIMESTAMP_SUB(fc.dischtime, INTERVAL 12 HOUR)
    AND pr.starttime <= fc.dischtime
    AND (
      LOWER(pr.drug) LIKE '%insulin%'
      OR LOWER(pr.drug) LIKE '%metformin%'
      OR LOWER(pr.drug) LIKE '%glipizide%'
      OR LOWER(pr.drug) LIKE '%glyburide%'
      OR LOWER(pr.drug) LIKE '%glimepiride%'
      OR LOWER(pr.drug) LIKE '%pioglitazone%'
      OR LOWER(pr.drug) LIKE '%sitagliptin%'
      OR LOWER(pr.drug) LIKE '%linagliptin%'
      OR LOWER(pr.drug) LIKE '%saxagliptin%'
      OR LOWER(pr.drug) LIKE '%exenatide%'
      OR LOWER(pr.drug) LIKE '%liraglutide%'
      OR LOWER(pr.drug) LIKE '%dulaglutide%'
      OR LOWER(pr.drug) LIKE '%semaglutide%'
      OR LOWER(pr.drug) LIKE '%canagliflozin%'
      OR LOWER(pr.drug) LIKE '%dapagliflozin%'
      OR LOWER(pr.drug) LIKE '%empagliflozin%'
      OR LOWER(pr.drug) LIKE '%ertugliflozin%'
    )
),
-- Beta-blockers
beta_first48 AS (
  SELECT COUNT(DISTINCT fc.hadm_id) AS n_first
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= fc.admittime
    AND pr.starttime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)
    AND (
      LOWER(pr.drug) LIKE '%atenolol%'
      OR LOWER(pr.drug) LIKE '%metoprolol%'
      OR LOWER(pr.drug) LIKE '%bisoprolol%'
      OR LOWER(pr.drug) LIKE '%carvedilol%'
      OR LOWER(pr.drug) LIKE '%nebivolol%'
      OR LOWER(pr.drug) LIKE '%propranolol%'
      OR LOWER(pr.drug) LIKE '%nadolol%'
      OR LOWER(pr.drug) LIKE '%sotalol%'
      OR LOWER(pr.drug) LIKE '%labetalol%'
      OR LOWER(pr.drug) LIKE '%esmolol%'
    )
),
beta_last12 AS (
  SELECT COUNT(DISTINCT fc.hadm_id) AS n_last
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= TIMESTAMP_SUB(fc.dischtime, INTERVAL 12 HOUR)
    AND pr.starttime <= fc.dischtime
    AND (
      LOWER(pr.drug) LIKE '%atenolol%'
      OR LOWER(pr.drug) LIKE '%metoprolol%'
      OR LOWER(pr.drug) LIKE '%bisoprolol%'
      OR LOWER(pr.drug) LIKE '%carvedilol%'
      OR LOWER(pr.drug) LIKE '%nebivolol%'
      OR LOWER(pr.drug) LIKE '%propranolol%'
      OR LOWER(pr.drug) LIKE '%nadolol%'
      OR LOWER(pr.drug) LIKE '%sotalol%'
      OR LOWER(pr.drug) LIKE '%labetalol%'
      OR LOWER(pr.drug) LIKE '%esmolol%'
    )
),
-- ACEi/ARB/ARNI (RAAS)
raas_first48 AS (
  SELECT COUNT(DISTINCT fc.hadm_id) AS n_first
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= fc.admittime
    AND pr.starttime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)
    AND (
      -- ACEi
      LOWER(pr.drug) LIKE '%captopril%'
      OR LOWER(pr.drug) LIKE '%enalapril%'
      OR LOWER(pr.drug) LIKE '%lisinopril%'
      OR LOWER(pr.drug) LIKE '%benazepril%'
      OR LOWER(pr.drug) LIKE '%quinapril%'
      OR LOWER(pr.drug) LIKE '%ramipril%'
      OR LOWER(pr.drug) LIKE '%perindopril%'
      OR LOWER(pr.drug) LIKE '%trandolapril%'
      OR LOWER(pr.drug) LIKE '%fosinopril%'
      -- ARB
      OR LOWER(pr.drug) LIKE '%losartan%'
      OR LOWER(pr.drug) LIKE '%valsartan%'
      OR LOWER(pr.drug) LIKE '%irbesartan%'
      OR LOWER(pr.drug) LIKE '%candesartan%'
      OR LOWER(pr.drug) LIKE '%telmisartan%'
      OR LOWER(pr.drug) LIKE '%olmesartan%'
      OR LOWER(pr.drug) LIKE '%azilsartan%'
      -- ARNI
      OR LOWER(pr.drug) LIKE '%sacubitril%'
      OR LOWER(pr.drug) LIKE '%entresto%'
    )
),
raas_last12 AS (
  SELECT COUNT(DISTINCT fc.hadm_id) AS n_last
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= TIMESTAMP_SUB(fc.dischtime, INTERVAL 12 HOUR)
    AND pr.starttime <= fc.dischtime
    AND (
      -- ACEi
      LOWER(pr.drug) LIKE '%captopril%'
      OR LOWER(pr.drug) LIKE '%enalapril%'
      OR LOWER(pr.drug) LIKE '%lisinopril%'
      OR LOWER(pr.drug) LIKE '%benazepril%'
      OR LOWER(pr.drug) LIKE '%quinapril%'
      OR LOWER(pr.drug) LIKE '%ramipril%'
      OR LOWER(pr.drug) LIKE '%perindopril%'
      OR LOWER(pr.drug) LIKE '%trandolapril%'
      OR LOWER(pr.drug) LIKE '%fosinopril%'
      -- ARB
      OR LOWER(pr.drug) LIKE '%losartan%'
      OR LOWER(pr.drug) LIKE '%valsartan%'
      OR LOWER(pr.drug) LIKE '%irbesartan%'
      OR LOWER(pr.drug) LIKE '%candesartan%'
      OR LOWER(pr.drug) LIKE '%telmisartan%'
      OR LOWER(pr.drug) LIKE '%olmesartan%'
      OR LOWER(pr.drug) LIKE '%azilsartan%'
      -- ARNI
      OR LOWER(pr.drug) LIKE '%sacubitril%'
      OR LOWER(pr.drug) LIKE '%entresto%'
    )
),
-- Loop diuretics
loop_first48 AS (
  SELECT COUNT(DISTINCT fc.hadm_id) AS n_first
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= fc.admittime
    AND pr.starttime <= TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)
    AND (
      LOWER(pr.drug) LIKE '%furosemide%'
      OR LOWER(pr.drug) LIKE '%lasix%'
      OR LOWER(pr.drug) LIKE '%bumetanide%'
      OR LOWER(pr.drug) LIKE '%bumex%'
      OR LOWER(pr.drug) LIKE '%torsemide%'
      OR LOWER(pr.drug) LIKE '%demadex%'
    )
),
loop_last12 AS (
  SELECT COUNT(DISTINCT fc.hadm_id) AS n_last
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= TIMESTAMP_SUB(fc.dischtime, INTERVAL 12 HOUR)
    AND pr.starttime <= fc.dischtime
    AND (
      LOWER(pr.drug) LIKE '%furosemide%'
      OR LOWER(pr.drug) LIKE '%lasix%'
      OR LOWER(pr.drug) LIKE '%bumetanide%'
      OR LOWER(pr.drug) LIKE '%bumex%'
      OR LOWER(pr.drug) LIKE '%torsemide%'
      OR LOWER(pr.drug) LIKE '%demadex%'
    )
)
-- Results
SELECT 'Antidiabetics' AS medication_class,
  ROUND(af.n_first * 100.0 / tc.total_patients, 2) AS first_48h_rate_pct,
  ROUND(al.n_last * 100.0 / tc.total_patients, 2) AS last_12h_rate_pct,
  ROUND((af.n_first - al.n_last) * 100.0 / tc.total_patients, 2) AS net_change_pct
FROM antidiabetic_first48 af, antidiabetic_last12 al, total_cohort tc
UNION ALL
SELECT 'Beta-blockers' AS medication_class,
  ROUND(bf.n_first * 100.0 / tc.total_patients, 2) AS first_48h_rate_pct,
  ROUND(bl.n_last * 100.0 / tc.total_patients, 2) AS last_12h_rate_pct,
  ROUND((bf.n_first - bl.n_last) * 100.0 / tc.total_patients, 2) AS net_change_pct
FROM beta_first48 bf, beta_last12 bl, total_cohort tc
UNION ALL
SELECT 'ACEi/ARB/ARNI' AS medication_class,
  ROUND(rf.n_first * 100.0 / tc.total_patients, 2) AS first_48h_rate_pct,
  ROUND(rl.n_last * 100.0 / tc.total_patients, 2) AS last_12h_rate_pct,
  ROUND((rf.n_first - rl.n_last) * 100.0 / tc.total_patients, 2) AS net_change_pct
FROM raas_first48 rf, raas_last12 rl, total_cohort tc
UNION ALL
SELECT 'Loop Diuretics' AS medication_class,
  ROUND(lf.n_first * 100.0 / tc.total_patients, 2) AS first_48h_rate_pct,
  ROUND(ll.n_last * 100.0 / tc.total_patients, 2) AS last_12h_rate_pct,
  ROUND((lf.n_first - ll.n_last) * 100.0 / tc.total_patients, 2) AS net_change_pct
FROM loop_first48 lf, loop_last12 ll, total_cohort tc
ORDER BY medication_class;
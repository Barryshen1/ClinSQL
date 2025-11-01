WITH lgib_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%lower gi bleed%'
     OR LOWER(long_title) LIKE '%gastrointestinal hemorrhage%'
     OR LOWER(long_title) LIKE '%hematochezia%'
     OR LOWER(long_title) LIKE '%rectum and anus%'
),

radiology_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE SUBSTR(icd_code, 1, 2) IN ('BW', 'BT')
),

target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 71 AND 81
),

lgib_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    i.stay_id,
    i.los AS icu_los,
    CASE
      WHEN i.los BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN i.los BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other'
    END AS los_category,
    d.seq_num,
    CASE
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_role
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN target_patients tp ON a.subject_id = tp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN lgib_codes lc
    ON d.icd_code = lc.icd_code AND d.icd_version = lc.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE i.los BETWEEN 1 AND 7
),

radiology_procedures AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS radiology_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN radiology_codes rc
    ON p.icd_code = rc.icd_code AND p.icd_version = rc.icd_version
  GROUP BY p.hadm_id
)

SELECT
  l.los_category,
  l.diagnosis_role,
  AVG(COALESCE(r.radiology_count, 0)) AS mean_radiology_per_admission
FROM lgib_admissions l
LEFT JOIN radiology_procedures r
  ON l.hadm_id = r.hadm_id
WHERE l.los_category IN ('1-3 days', '4-7 days')
GROUP BY l.los_category, l.diagnosis_role
ORDER BY l.los_category, l.diagnosis_role;
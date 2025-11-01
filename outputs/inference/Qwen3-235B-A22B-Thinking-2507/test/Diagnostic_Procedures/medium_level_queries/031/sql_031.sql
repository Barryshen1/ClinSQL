WITH aki_admissions AS (
  SELECT 
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE 
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND dd.icd_code IN ('N170', 'N171', 'N172', 'N178'))
          OR 
          (d.icd_version = 9 AND dd.icd_code IN ('5845', '5846', '5847', '5848', '5849'))
        )
    )
),
aki_admissions_filtered AS (
  SELECT 
    hadm_id,
    hospital_los
  FROM aki_admissions
  WHERE 
    age_at_admission BETWEEN 38 AND 48
    AND hospital_los BETWEEN 1 AND 7
),
lab_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY hadm_id
),
micro_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS micro_count
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents`
  GROUP BY hadm_id
),
icu_flag AS (
  SELECT 
    hadm_id, 
    1 AS icu_use
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
base AS (
  SELECT 
    a.hadm_id,
    a.hospital_los,
    COALESCE(i.icu_use, 0) AS icu_use,
    COALESCE(l.lab_count, 0) + COALESCE(m.micro_count, 0) AS total_diagnostics
  FROM aki_admissions_filtered a
  LEFT JOIN icu_flag i 
    ON a.hadm_id = i.hadm_id
  LEFT JOIN lab_counts l 
    ON a.hadm_id = l.hadm_id
  LEFT JOIN micro_counts m 
    ON a.hadm_id = m.hadm_id
)
SELECT
  CASE 
    WHEN hospital_los BETWEEN 1 AND 4 THEN '1-4'
    WHEN hospital_los BETWEEN 5 AND 7 THEN '5-7'
  END AS los_group,
  icu_use,
  AVG(total_diagnostics) AS mean_diagnostics,
  MIN(total_diagnostics) AS min_diagnostics,
  MAX(total_diagnostics) AS max_diagnostics
FROM base
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;
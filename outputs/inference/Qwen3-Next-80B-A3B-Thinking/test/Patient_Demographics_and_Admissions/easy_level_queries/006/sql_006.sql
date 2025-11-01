WITH eligible_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (di.long_title LIKE '%sepsis%' OR di.long_title LIKE '%septicemia%')
),
icu_los_per_admission AS (
  SELECT i.hadm_id, SUM(i.los) AS total_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  WHERE i.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
  GROUP BY i.hadm_id
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_los) AS median_los
FROM icu_los_per_admission;
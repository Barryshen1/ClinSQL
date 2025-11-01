WITH aki_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5845', '5846', '5847', '5848', '5849'))
      OR (d.icd_version = 10 AND d.icd_code IN ('N170', 'N171', 'N172', 'N178', 'N179'))
    )
),
icu_stays AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime, 
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN aki_admissions a 
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),
first_icu AS (
  SELECT 
    subject_id, 
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_rank
  FROM icu_stays
)
SELECT 
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(25)] AS los_25th_percentile
FROM first_icu
WHERE stay_rank = 1;
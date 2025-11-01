WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 82 AND 92
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code IN ('N170', 'N171', 'N172', 'N178', 'N179')
        AND d.icd_version = 10
    )
),
first_icu_stays AS (
  SELECT 
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_admissions e
    ON i.hadm_id = e.hadm_id
)
SELECT 
  PERCENTILE_CONT(los, 0.25) OVER () AS p25_los
FROM first_icu_stays
WHERE rn = 1
LIMIT 1;
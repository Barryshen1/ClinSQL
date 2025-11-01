WITH eligible_patients AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
first_icu_stays_with_aki AS (
  SELECT 
    fs.subject_id,
    fs.los
  FROM eligible_patients fs
  WHERE fs.rn = 1
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = fs.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '584%')
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
        )
    )
)
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_los_days
FROM first_icu_stays_with_aki;
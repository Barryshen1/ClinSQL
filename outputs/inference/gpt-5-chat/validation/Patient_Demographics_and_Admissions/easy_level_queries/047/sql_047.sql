WITH aki_patients AS (
  SELECT DISTINCT p.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
),
first_icu_stays AS (
  SELECT
    a.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY i.intime) AS rn
  FROM aki_patients a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id
   AND a.hadm_id = i.hadm_id
)
SELECT
  PERCENTILE_CONT(los, 0.25) OVER() AS los_25th_percentile_days
FROM first_icu_stays
WHERE rn = 1;
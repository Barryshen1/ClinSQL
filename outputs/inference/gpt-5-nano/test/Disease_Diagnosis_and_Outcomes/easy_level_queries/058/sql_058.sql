WITH hemorrhagic_primary AS (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
   AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
    AND LOWER(dd.long_title) LIKE '%hemorrhage%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(74)] AS p75_hospital_los_days
FROM hemorrhagic_primary;
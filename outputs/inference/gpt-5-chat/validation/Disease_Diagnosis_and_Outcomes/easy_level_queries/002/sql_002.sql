WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    -- calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit,
    adm.admittime,
    adm.dischtime,
    -- LOS in days (fractional)
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 52 AND 62
    AND dx.seq_num = 1
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
    )
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_hosp_los_days
FROM cohort;
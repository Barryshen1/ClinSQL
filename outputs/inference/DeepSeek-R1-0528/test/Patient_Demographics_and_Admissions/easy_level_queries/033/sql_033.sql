WITH cohort AS (
  SELECT
    adm.hadm_id,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code
        AND proc.icd_version = dicd.icd_version
      WHERE
        adm.hadm_id = proc.hadm_id
        AND dicd.long_title LIKE '%dialysis%'
    )
)
SELECT STDDEV_POP(los_days) AS sd_length_of_stay_days
FROM cohort;
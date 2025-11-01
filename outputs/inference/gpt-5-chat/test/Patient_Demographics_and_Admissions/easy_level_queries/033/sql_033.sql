WITH dialysis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON adm.subject_id = proc.subject_id
    AND adm.hadm_id = proc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND LOWER(dproc.long_title) LIKE '%dialysis%'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT STDDEV(los_days) AS sd_los_days
FROM dialysis_admissions;
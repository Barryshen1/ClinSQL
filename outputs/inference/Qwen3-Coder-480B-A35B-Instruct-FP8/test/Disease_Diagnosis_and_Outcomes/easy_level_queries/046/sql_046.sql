SELECT
  STDDEV_SAMP(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS los_sd_days
FROM
  physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
  ON adm.hadm_id = dx.hadm_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 43 AND 53
  AND dx.seq_num = 1
  AND (
    (dx.icd_version = 9 AND dx.icd_code = '431')
    OR
    (dx.icd_version = 10 AND dx.icd_code = 'I619')
  );
SELECT
  APPROX_QUANTILES(DATETIME_DIFF(ad.dischtime, ad.admittime, DAY), 100)[OFFSET(75)] AS los_75th_percentile
FROM
  physionet-data.mimiciv_3_1_hosp.admissions ad
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON ad.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  ON ad.hadm_id = di.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 37 AND 47
  AND di.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '5849') OR
    (d.icd_version = 10 AND d.icd_code = 'N179')
  )
  AND ad.dischtime IS NOT NULL
  AND ad.admittime IS NOT NULL;
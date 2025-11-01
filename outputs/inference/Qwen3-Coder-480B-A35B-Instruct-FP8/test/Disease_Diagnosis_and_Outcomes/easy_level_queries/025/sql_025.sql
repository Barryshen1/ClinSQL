SELECT
  STDDEV_SAMP(icu.los) AS los_sd
FROM
  physionet-data.mimiciv_3_1_hosp.patients pat
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON adm.hadm_id = icu.hadm_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 77 AND 87
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code IN (
      '53021', '5310', '5312', '5314', '5316',
      '5320', '5322', '5324', '5326',
      '5330', '5332', '5334', '5336',
      '5340', '5342', '5344', '5346'
    ))
    OR
    (diag.icd_version = 10 AND diag.icd_code IN (
      'K920', 'K921', 'K922',
      'K250', 'K252', 'K254', 'K256',
      'K260', 'K262', 'K264', 'K266',
      'K270', 'K272', 'K274', 'K276',
      'K280', 'K282', 'K284', 'K286'
    ))
  );
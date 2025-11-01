SELECT
  STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND d.seq_num = 1
  AND (
    REGEXP_CONTAINS(LOWER(dd.long_title), r'upper gastrointestinal.*(hemorrhage|bleed)') OR
    REGEXP_CONTAINS(LOWER(dd.long_title), r'esophageal.*(hemorrhage|bleed)') OR
    REGEXP_CONTAINS(LOWER(dd.long_title), r'gastric.*(hemorrhage|bleed)') OR
    REGEXP_CONTAINS(LOWER(dd.long_title), r'duodenal.*(hemorrhage|bleed)')
  )
  AND a.dischtime IS NOT NULL;
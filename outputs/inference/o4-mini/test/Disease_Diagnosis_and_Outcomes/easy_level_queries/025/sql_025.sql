SELECT
  STDDEV_SAMP(
    TIMESTAMP_DIFF(ad.dischtime, ad.admittime, DAY)
  ) AS sd_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` ad
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ad.subject_id = p.subject_id
-- Primary diagnosis
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ad.subject_id = d.subject_id
    AND ad.hadm_id    = d.hadm_id
    AND d.seq_num     = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code    = dicd.icd_code
    AND d.icd_version = dicd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND LOWER(dicd.long_title) LIKE '%upper gastrointestinal bleeding%'
;
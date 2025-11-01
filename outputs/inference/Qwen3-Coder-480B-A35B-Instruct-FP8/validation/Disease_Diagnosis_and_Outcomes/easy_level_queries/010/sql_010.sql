SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM (
  SELECT
    ad.hadm_id,
    DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` ad
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pa
  ON
    ad.subject_id = pa.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    ad.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
  ON
    di.icd_code = ddi.icd_code
    AND di.icd_version = ddi.icd_version
  WHERE
    pa.gender = 'F'
    AND di.seq_num = 1
    AND LOWER(ddi.long_title) LIKE '%chronic obstructive pulmonary disease exacerbation%'
    AND ad.admittime IS NOT NULL
    AND ad.dischtime IS NOT NULL
    AND ad.admittime >= DATETIME(pa.anchor_year, 1, 1, 0, 0, 0)
    AND (
      pa.anchor_age - (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)
    ) BETWEEN 49 AND 59
);
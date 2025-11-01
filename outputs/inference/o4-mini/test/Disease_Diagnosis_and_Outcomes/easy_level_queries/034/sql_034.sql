SELECT
  quantiles[OFFSET(1)] AS q1_los_days,
  quantiles[OFFSET(3)] AS q3_los_days
FROM (
  SELECT
    APPROX_QUANTILES(
      DATE_DIFF(a.dischtime, a.admittime, DAY),
      4
    ) AS quantiles
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%sepsis%'
)
;
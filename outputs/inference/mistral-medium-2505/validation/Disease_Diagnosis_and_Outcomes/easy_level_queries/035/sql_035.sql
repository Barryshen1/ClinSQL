WITH upper_gi_bleeding_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 70
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_code IN (
      'K250', 'K251', 'K252', 'K253', 'K254', 'K255', 'K256', 'K257', 'K259',  -- Gastric ulcer
      'K260', 'K261', 'K262', 'K263', 'K264', 'K265', 'K266', 'K269',  -- Duodenal ulcer
      'K270', 'K271', 'K272', 'K273', 'K274', 'K275', 'K276', 'K279',  -- Peptic ulcer, site unspecified
      'K280', 'K281', 'K282', 'K283', 'K284', 'K285', 'K286', 'K289',  -- Gastrojejunal ulcer
      'K920', 'K921', 'K922'  -- Hematemesis, melena, GI hemorrhage
    )
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS percentile_75_los_days
FROM
  upper_gi_bleeding_admissions
LIMIT 1;
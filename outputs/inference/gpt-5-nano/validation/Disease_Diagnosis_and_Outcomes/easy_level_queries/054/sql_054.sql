with hemorrhagic_primary AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'I6%') OR
      (di.icd_version = 9  AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%'))
    )
),

filtered_los AS (
  SELECT
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM hemorrhagic_primary)
    AND UPPER(p.gender) = 'MALE'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0
)

SELECT STDDEV_POP(los_days) AS sd_los_days
FROM filtered_los
WHERE los_days IS NOT NULL;
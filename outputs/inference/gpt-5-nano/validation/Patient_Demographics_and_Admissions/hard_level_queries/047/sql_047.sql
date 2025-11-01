WITH index_candidates AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE
    a.admission_type = 'EMERGENCY'                                -- admitted from ED (proxy)
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(p.gender) IN ('f', 'female')
    AND a.insurance = 'Medicare'
    AND d.seq_num = 1                                               -- principal diagnosis
    AND (
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I6[0-2]'))  -- ICD-10 hemorrhagic stroke
          OR
          (d.icd_version = 9 AND CAST(d.icd_code AS INT64) BETWEEN 430 AND 432)  -- ICD-9 hemorrhagic stroke
        )
),
readmission_flags AS (
  SELECT
    idx.subject_id,
    idx.hadm_id,
    idx.admittime,
    idx.dischtime,
    idx.index_los_days,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = idx.subject_id
        AND a2.hadm_id != idx.hadm_id
        AND a2.admittime > idx.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(idx.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30
  FROM index_candidates AS idx
)
SELECT
  100.0 * SUM(CASE WHEN readmit_30 THEN 1 ELSE 0 END) / COUNT(*) AS readmission_rate_percent,
  MEDIAN(CASE WHEN readmit_30 THEN index_los_days END) AS median_index_los_readmit_days,
  MEDIAN(CASE WHEN NOT readmit_30 THEN index_los_days END) AS median_index_los_nonreadmit_days,
  100.0 * SUM(CASE WHEN index_los_days > 4 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_gt4
FROM readmission_flags;
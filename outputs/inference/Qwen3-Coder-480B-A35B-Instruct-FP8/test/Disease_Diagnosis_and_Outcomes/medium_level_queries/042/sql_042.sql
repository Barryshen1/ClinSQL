WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    a.discharge_location,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '8+'
    END AS los_group
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND dd.icd_code LIKE 'I21%'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND dd.icd_code IN ('R570', 'R578', 'R579', 'J9600', 'J9601', 'J9602', 'J9690', 'J9692')
    )
),
grouped_stats AS (
  SELECT
    los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
    discharge_location,
    COUNT(discharge_location) AS discharge_count
  FROM
    cohort
  GROUP BY
    los_group, discharge_location
)
SELECT
  los_group,
  mortality_percent,
  median_los,
  discharge_location,
  discharge_count
FROM
  grouped_stats
ORDER BY
  los_group, discharge_count DESC;
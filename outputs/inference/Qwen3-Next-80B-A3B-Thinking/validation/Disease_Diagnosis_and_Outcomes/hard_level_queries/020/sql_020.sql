WITH amipatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = '9' AND d.icd_code LIKE '410%') OR
          (d.icd_version = '10' AND d.icd_code LIKE 'I21%')
        )
    )
),
filtered_amipatients AS (
  SELECT *
  FROM amipatients
  WHERE age_at_admission BETWEEN 46 AND 56
),
complications AS (
  SELECT
    d.hadm_id,
    SUM(
      CASE
        WHEN (d.icd_version = '9' AND d.icd_code = '78551') THEN 1
        WHEN (d.icd_version = '9' AND d.icd_code LIKE '428%') THEN 1
        WHEN (d.icd_version = '9' AND d.icd_code LIKE '427%') THEN 1
        WHEN (d.icd_version = '9' AND d.icd_code IN ('43401', '43411', '43491', '436')) THEN 1
        WHEN (d.icd_version = '9' AND d.icd_code LIKE '584%') THEN 1
        WHEN (d.icd_version = '10' AND d.icd_code = 'R570') THEN 1
        WHEN (d.icd_version = '10' AND d.icd_code LIKE 'I50%') THEN 1
        WHEN (d.icd_version = '10' AND d.icd_code LIKE 'I47%') THEN 1
        WHEN (d.icd_version = '10' AND d.icd_code LIKE 'I48%') THEN 1
        WHEN (d.icd_version = '10' AND d.icd_code LIKE 'I63%') THEN 1
        WHEN (d.icd_version = '10' AND d.icd_code = 'I64') THEN 1
        WHEN (d.icd_version = '10' AND d.icd_code LIKE 'N17%') THEN 1
        ELSE 0
      END
    ) AS num_complications
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
),
composite_scores AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.age_at_admission,
    COALESCE(c.num_complications, 0) AS num_complications,
    f.hospital_expire_flag,
    f.admittime,
    f.dischtime,
    (f.age_at_admission + COALESCE(c.num_complications, 0)) AS composite_score
  FROM filtered_amipatients f
  LEFT JOIN complications c
    ON f.hadm_id = c.hadm_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
    CASE WHEN hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(dischtime, admittime, DAY) ELSE NULL END AS survivor_los
  FROM composite_scores
)
SELECT
  quintile,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
  AVG(CAST(num_complications > 0 AS FLOAT64)) * 100 AS complication_pct,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY survivor_los) AS median_survivor_los
FROM quintiles
GROUP BY quintile;
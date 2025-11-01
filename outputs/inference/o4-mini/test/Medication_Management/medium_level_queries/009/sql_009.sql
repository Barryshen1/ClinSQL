WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    -- length of stay ≥ 48 hours
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    -- diabetes AND acute heart failure
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
        ON d.icd_code = dicd.icd_code
       AND d.icd_version = dicd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
        ON d.icd_code = dicd.icd_code
       AND d.icd_version = dicd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%acute heart failure%'
    )
),

-- total cohort size
cohort_size AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_cohort
  FROM cohort
),

-- counts of initiations in each window
init_counts AS (
  SELECT
    SUM(IF(first24_insulin > 0, 1, 0)) AS n_first_insulin,
    SUM(IF(first24_oral > 0, 1, 0))   AS n_first_oral,
    SUM(IF(last24_insulin  > 0, 1, 0)) AS n_last_insulin,
    SUM(IF(last24_oral  > 0, 1, 0))   AS n_last_oral
  FROM (
    SELECT
      c.hadm_id,
      -- first 24h
      COUNTIF(
        LOWER(p.drug) LIKE '%insulin%' 
        AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
      ) AS first24_insulin,
      COUNTIF(
        p.drug_type = 'ORAL'
        AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
      ) AS first24_oral,
      -- last 24h
      COUNTIF(
        LOWER(p.drug) LIKE '%insulin%'
        AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
      ) AS last24_insulin,
      COUNTIF(
        p.drug_type = 'ORAL'
        AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
      ) AS last24_oral
    FROM
      cohort AS c
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
        ON c.hadm_id = p.hadm_id
    GROUP BY
      c.hadm_id
  )
)

SELECT
  ROUND(n_first_insulin  * 100.0 / n_cohort, 1) AS pct_first24_insulin,
  ROUND(n_last_insulin   * 100.0 / n_cohort, 1) AS pct_last24_insulin,
  ROUND((n_last_insulin  * 100.0 / n_cohort) - (n_first_insulin * 100.0 / n_cohort), 1)
    AS abs_pp_diff_insulin,
  ROUND(n_first_oral     * 100.0 / n_cohort, 1) AS pct_first24_oral,
  ROUND(n_last_oral      * 100.0 / n_cohort, 1) AS pct_last24_oral,
  ROUND((n_last_oral     * 100.0 / n_cohort) - (n_first_oral   * 100.0 / n_cohort), 1)
    AS abs_pp_diff_oral
FROM
  init_counts,
  cohort_size;
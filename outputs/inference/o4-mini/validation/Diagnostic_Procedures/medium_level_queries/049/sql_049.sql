WITH sepsis_adms AS (
  -- Admissions of male patients age 87–97 with sepsis but without septic shock
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON dx.icd_code = dd.icd_code
     AND dx.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND LOWER(dd.long_title) LIKE '%sepsis%'
    AND DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) BETWEEN 1 AND 7
    -- Exclude any admission that has a septic shock diagnosis
    AND adm.hadm_id NOT IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON dx2.icd_code = dd2.icd_code
       AND dx2.icd_version = dd2.icd_version
      WHERE LOWER(dd2.long_title) LIKE '%septic shock%'
    )
  GROUP BY
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
),

proc_counts AS (
  -- Count distinct diagnostic procedures per admission and classify by LOS bucket
  SELECT
    sa.subject_id,
    sa.hadm_id,
    CASE
      WHEN sa.los BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN sa.los BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_bucket,
    COUNT(DISTINCT proc.icd_code) AS num_procedures
  FROM
    sepsis_adms AS sa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON sa.hadm_id = proc.hadm_id
  GROUP BY
    sa.subject_id,
    sa.hadm_id,
    los_bucket
)

SELECT
  los_bucket,
  AVG(num_procedures) AS mean_diagnostic_procedures
FROM
  proc_counts
WHERE
  los_bucket IS NOT NULL
GROUP BY
  los_bucket
ORDER BY
  los_bucket;
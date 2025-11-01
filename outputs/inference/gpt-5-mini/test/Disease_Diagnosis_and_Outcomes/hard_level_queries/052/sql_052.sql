WITH
eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
             di.icd_code IN ('J44.1','J44.0','49121','491.21','491.20','491.2')
             OR (
               (COALESCE(LOWER(dd.long_title), '') LIKE '%copd%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%obstructive pulmonary%')
               AND (COALESCE(LOWER(dd.long_title), '') LIKE '%exacerb%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%acute%')
             )
        )
    )
),

adm_comorbidity_flags AS (
  SELECT
    ea.*,
    TIMESTAMP_DIFF(ea.dischtime, ea.admittime, DAY) AS los_days,

    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = ea.hadm_id
        AND NOT (COALESCE(LOWER(dd.long_title), '') LIKE '%copd%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%obstructive pulmonary%')
        AND (COALESCE(LOWER(dd.long_title), '') LIKE '%heart failure%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%congestive heart%')
    ) THEN 1 ELSE 0 END AS flag_chf,

    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = ea.hadm_id
        AND NOT (COALESCE(LOWER(dd.long_title), '') LIKE '%copd%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%obstructive pulmonary%')
        AND (COALESCE(LOWER(dd.long_title), '') LIKE '%diabetes%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%diabetic%')
    ) THEN 1 ELSE 0 END AS flag_diabetes,

    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = ea.hadm_id
        AND NOT (COALESCE(LOWER(dd.long_title), '') LIKE '%copd%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%obstructive pulmonary%')
        AND (
          COALESCE(LOWER(dd.long_title), '') LIKE '%renal failure%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%acute kidney%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%acute renal%'
        )
    ) THEN 1 ELSE 0 END AS flag_renal,

    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = ea.hadm_id
        AND NOT (COALESCE(LOWER(dd.long_title), '') LIKE '%copd%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%obstructive pulmonary%')
        AND (COALESCE(LOWER(dd.long_title), '') LIKE '%malignancy%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%neoplasm%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%cancer%')
    ) THEN 1 ELSE 0 END AS flag_cancer,

    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = ea.hadm_id
        AND NOT (COALESCE(LOWER(dd.long_title), '') LIKE '%copd%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%obstructive pulmonary%')
        AND (COALESCE(LOWER(dd.long_title), '') LIKE '%cerebrovascular%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%stroke%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%intracerebral%')
    ) THEN 1 ELSE 0 END AS flag_cva,

    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = ea.hadm_id
        AND NOT (COALESCE(LOWER(dd.long_title), '') LIKE '%copd%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%obstructive pulmonary%')
        AND (COALESCE(LOWER(dd.long_title), '') LIKE '%liver%' OR COALESCE(LOWER(dd.long_title), '') LIKE '%cirrhosis%')
    ) THEN 1 ELSE 0 END AS flag_liver,

    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = ea.hadm_id
        AND (
          COALESCE(LOWER(dd.long_title), '') LIKE '%sepsis%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%septic%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%respiratory failure%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%acute respiratory failure%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%acute renal%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%acute kidney%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%myocardial infarction%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%infarction%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%stroke%' OR
          COALESCE(LOWER(dd.long_title), '') LIKE '%cerebrovascular%'
        )
    ) THEN 1 ELSE 0 END AS major_complication_flag

  FROM eligible_admissions ea
),

adm_scores AS (
  SELECT
    acf.*,
    (flag_chf + flag_diabetes + flag_renal + flag_cancer + flag_cva + flag_liver) AS composite_score,
    CASE
      WHEN acf.dod IS NOT NULL
        AND DATE(acf.dod) >= DATE(acf.admittime)
        AND DATE_DIFF(DATE(acf.dod), DATE(acf.admittime), DAY) <= 90
      THEN 1 ELSE 0
    END AS died_within_90d,
    CASE WHEN acf.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS survived_hospital
  FROM adm_comorbidity_flags acf
),

adm_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY composite_score) AS quartile
  FROM adm_scores
),

overall_stats AS (
  SELECT
    ROUND(SAFE_DIVIDE(SUM(died_within_90d), COUNT(*)), 4) AS overall_75_85_female_mortality_90d
  FROM adm_quartiles
)

SELECT
  quartile_label,
  n_admissions,
  mortality_90d_rate,
  major_complication_rate,
  median_survivor_los_days,
  overall_75_85_female_mortality_90d
FROM (
  SELECT
    CAST(quartile AS STRING) AS quartile_label,
    COUNT(*) AS n_admissions,
    ROUND(SAFE_DIVIDE(SUM(died_within_90d), COUNT(*)), 4) AS mortality_90d_rate,
    ROUND(SAFE_DIVIDE(SUM(major_complication_flag), COUNT(*)), 4) AS major_complication_rate,
    APPROX_QUANTILES(IF(survived_hospital = 1, los_days, NULL), 2)[OFFSET(1)] AS median_survivor_los_days,
    os.overall_75_85_female_mortality_90d
  FROM adm_quartiles aq
  CROSS JOIN overall_stats os
  GROUP BY quartile, os.overall_75_85_female_mortality_90d

  UNION ALL

  SELECT
    'All (75-85 female)' AS quartile_label,
    COUNT(*) AS n_admissions,
    ROUND(SAFE_DIVIDE(SUM(died_within_90d), COUNT(*)), 4) AS mortality_90d_rate,
    ROUND(SAFE_DIVIDE(SUM(major_complication_flag), COUNT(*)), 4) AS major_complication_rate,
    APPROX_QUANTILES(IF(survived_hospital = 1, los_days, NULL), 2)[OFFSET(1)] AS median_survivor_los_days,
    (SELECT overall_75_85_female_mortality_90d FROM overall_stats) AS overall_75_85_female_mortality_90d
  FROM adm_quartiles
) t
ORDER BY
  CASE WHEN quartile_label = 'All (75-85 female)' THEN 2 ELSE 1 END,
  SAFE_CAST(NULLIF(quartile_label, 'All (75-85 female)') AS INT64);
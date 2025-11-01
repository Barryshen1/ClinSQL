WITH
  stroke_admissions AS (
    SELECT DISTINCT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 52 AND 62
      AND (
        (
          d.icd_version = 9
          AND SUBSTR(d.icd_code, 1, 3) BETWEEN '430' AND '438'
        )
        OR (
          d.icd_version = 10
          AND SUBSTR(d.icd_code, 1, 3) BETWEEN 'I60' AND 'I69'
        )
      )
  ),
  charlson_components AS (
    SELECT
      d.hadm_id,
      CASE
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('410', '412') THEN 'MI'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('I21', 'I22') THEN 'MI'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) = '428' THEN 'CHF'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) = 'I50' THEN 'CHF'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('440', '441') OR SUBSTR(d.icd_code, 1, 4) IN ('4439') THEN 'PVD'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('I70', 'I71') OR SUBSTR(d.icd_code, 1, 4) IN ('I739') THEN 'PVD'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) BETWEEN '430' AND '438' THEN 'STROKE'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) BETWEEN 'I60' AND 'I69' THEN 'STROKE'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) = '290' OR SUBSTR(d.icd_code, 1, 4) IN ('2941', '3312') THEN 'DEMENTIA'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('F00', 'F01', 'F02', 'F03', 'G30') OR SUBSTR(d.icd_code, 1, 4) = 'G311' THEN 'DEMENTIA'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) BETWEEN '490' AND '496' THEN 'COPD'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) BETWEEN 'J40' AND 'J47' THEN 'COPD'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 4) IN ('7100', '7101', '7104', '7140', '7142') OR SUBSTR(d.icd_code, 1, 3) = '725' THEN 'RHEUM'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('M05', 'M06', 'M32', 'M33', 'M34') OR SUBSTR(d.icd_code, 1, 4) = 'M315' THEN 'RHEUM'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) BETWEEN '531' AND '534' THEN 'PUD'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) BETWEEN 'K25' AND 'K28' THEN 'PUD'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 4) IN ('5712', '5714', '5715', '5716') THEN 'MILD_LIVER'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('B18', 'K73', 'K74') OR SUBSTR(d.icd_code, 1, 4) IN ('K700', 'K701', 'K702', 'K703', 'K709', 'K717', 'K760') THEN 'MILD_LIVER'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 4) IN ('2500', '2501', '2502', '2503') THEN 'DIAB_UNCOMP'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 4) IN ('E100', 'E101', 'E109', 'E110', 'E111', 'E119', 'E120', 'E121', 'E129', 'E130', 'E131', 'E139', 'E140', 'E141', 'E149') THEN 'DIAB_UNCOMP'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 4) IN ('2504', '2505', '2506', '2507') THEN 'DIAB_COMP'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 4) IN ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113', 'E114', 'E115', 'E117', 'E122', 'E123', 'E124', 'E125', 'E127', 'E132', 'E133', 'E134', 'E135', 'E137', 'E142', 'E143', 'E144', 'E145', 'E147') THEN 'DIAB_COMP'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('342') OR SUBSTR(d.icd_code, 1, 4) = '3441' THEN 'PARAPLEGIA'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('G81', 'G82') OR SUBSTR(d.icd_code, 1, 4) = 'G041' THEN 'PARAPLEGIA'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('582', '583', '585', '586') OR SUBSTR(d.icd_code, 1, 4) = '5880' THEN 'RENAL'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('N18', 'N19') OR SUBSTR(d.icd_code, 1, 4) IN ('I120', 'I131') THEN 'RENAL'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(d.icd_code, 1, 4) BETWEEN '1740' AND '1958' OR SUBSTR(d.icd_code, 1, 3) BETWEEN '200' AND '208' THEN 'CANCER'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) BETWEEN 'C00' AND 'C76' OR SUBSTR(d.icd_code, 1, 3) IN ('C81', 'C82', 'C83', 'C84', 'C85', 'C88', 'C90', 'C91', 'C92', 'C93', 'C94', 'C95', 'C96', 'C97') THEN 'CANCER'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 4) IN ('5722', '5723', '5724') THEN 'SEVERE_LIVER'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 4) IN ('I850', 'I859', 'I864', 'I982', 'K704', 'K711', 'K721', 'K729', 'K765', 'K766', 'K767') THEN 'SEVERE_LIVER'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) BETWEEN '196' AND '199' THEN 'METS'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) BETWEEN 'C77' AND 'C80' THEN 'METS'
        WHEN d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) = '042' THEN 'HIV'
        WHEN d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('B20', 'B21', 'B22', 'B24') THEN 'HIV'
        ELSE NULL
      END AS condition
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    WHERE
      d.hadm_id IN (SELECT hadm_id FROM stroke_admissions)
  ),
  charlson_scores AS (
    SELECT
      hadm_id,
      SUM(score) AS charlson_score
    FROM
      (
        SELECT
          hadm_id,
          CASE
            WHEN condition IN ('MI', 'CHF', 'PVD', 'STROKE', 'DEMENTIA', 'COPD', 'RHEUM', 'PUD') THEN 1
            WHEN condition = 'MILD_LIVER' AND hadm_id NOT IN (SELECT hadm_id FROM charlson_components WHERE condition = 'SEVERE_LIVER') THEN 1
            WHEN condition = 'DIAB_UNCOMP' AND hadm_id NOT IN (SELECT hadm_id FROM charlson_components WHERE condition = 'DIAB_COMP') THEN 1
            WHEN condition IN ('PARAPLEGIA', 'RENAL') THEN 2
            WHEN condition = 'DIAB_COMP' THEN 2
            WHEN condition = 'CANCER' AND hadm_id NOT IN (SELECT hadm_id FROM charlson_components WHERE condition = 'METS') THEN 2
            WHEN condition = 'SEVERE_LIVER' THEN 3
            WHEN condition = 'METS' THEN 6
            WHEN condition = 'HIV' THEN 6
            ELSE 0
          END AS score
        FROM (SELECT DISTINCT hadm_id, condition FROM charlson_components WHERE condition IS NOT NULL)
      )
    GROUP BY
      hadm_id
  ),
  comorbidity_flags AS (
    SELECT
      hadm_id,
      MAX(
        CASE
          WHEN (
            (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) = '585')
            OR (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) = 'N18')
          ) THEN 1
          ELSE 0
        END
      ) AS has_ckd,
      MAX(
        CASE
          WHEN (
            (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) = '250')
            OR (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13'))
          ) THEN 1
          ELSE 0
        END
      ) AS has_diabetes
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    WHERE
      d.hadm_id IN (SELECT hadm_id FROM stroke_admissions)
    GROUP BY
      hadm_id
  ),
  cohort_final AS (
    SELECT
      sa.hadm_id,
      sa.hospital_expire_flag,
      CASE
        WHEN icu.stay_id IS NOT NULL THEN 'ICU'
        ELSE 'Non-ICU'
      END AS icu_category,
      CASE
        WHEN DATETIME_DIFF(sa.dischtime, sa.admittime, DAY) <= 5 THEN 'LOS <= 5 days'
        ELSE 'LOS > 5 days'
      END AS los_category,
      NTILE(3) OVER (ORDER BY COALESCE(cs.charlson_score, 0)) AS comorbidity_tertile,
      COALESCE(cf.has_ckd, 0) AS has_ckd,
      COALESCE(cf.has_diabetes, 0) AS has_diabetes
    FROM
      stroke_admissions AS sa
      LEFT JOIN (SELECT hadm_id, MIN(stay_id) as stay_id FROM `physionet-data.mimiciv_3_1_icu.icustays` GROUP BY hadm_id) AS icu ON sa.hadm_id = icu.hadm_id
      LEFT JOIN charlson_scores AS cs ON sa.hadm_id = cs.hadm_id
      LEFT JOIN comorbidity_flags AS cf ON sa.hadm_id = cf.hadm_id
  )
SELECT
  icu_category,
  los_category,
  comorbidity_tertile,
  COUNT(hadm_id) AS num_admissions,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_percent,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_percent
FROM
  cohort_final
GROUP BY
  icu_category,
  los_category,
  comorbidity_tertile
ORDER BY
  icu_category,
  los_category,
  comorbidity_tertile;
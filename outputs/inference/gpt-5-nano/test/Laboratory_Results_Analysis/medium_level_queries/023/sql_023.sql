WITH
  -- Base: select female patients with age-at-admission information
  base_patient AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'Female'
  ),

  -- ACS admissions: age 67-77 and ACS diagnosis (ICD codes with ACS long titles)
  acs_admissions AS (
    SELECT DISTINCT
      bp.subject_id,
      bp.hadm_id,
      bp.admittime,
      bp.dischtime,
      bp.hospital_expire_flag,
      bp.age_at_adm
    FROM base_patient AS bp
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON bp.subject_id = di.subject_id AND bp.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
      ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
    WHERE bp.age_at_adm BETWEEN 67 AND 77
      AND (
        LOWER(dic.long_title) LIKE '%acute myocardial infarction%'
        OR LOWER(dic.long_title) LIKE '%unstable angina%'
        OR LOWER(dic.long_title) LIKE '%coronary syndrome%'
        OR LOWER(dic.long_title) LIKE '%myocardial infarction%'
      )
  ),

  -- Initial Troponin T per ACS admission: earliest Troponin T value within the admission
  initial_troponin AS (
    SELECT
      acs.subject_id,
      acs.hadm_id,
      le.charttime,
      le.valuenum,
      acs.hospital_expire_flag
    FROM acs_admissions AS acs
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON le.subject_id = acs.subject_id
     AND le.hadm_id = acs.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dil
      ON le.itemid = dil.itemid
    WHERE LOWER(dil.label) LIKE '%troponin t%'
    QUALIFY ROW_NUMBER() OVER (
              PARTITION BY acs.subject_id, acs.hadm_id
              ORDER BY le.charttime ASC
            ) = 1
    AND le.valuenum IS NOT NULL
  ),

  -- Bring in the hospital_expire_flag for mortality calculations
  troponin_with_outcomes AS (
    SELECT
      it.subject_id,
      it.hadm_id,
      it.charttime,
      it.valuenum,
      it.hospital_expire_flag
    FROM initial_troponin AS it
  ),

  -- Classify into categories
  categorized AS (
    SELECT
      t.valuenum,
      t.hospital_expire_flag,
      CASE
        WHEN t.valuenum <= 0.04 THEN 'Normal'
        WHEN t.valuenum > 0.04 AND t.valuenum <= 0.1 THEN 'Borderline'
        WHEN t.valuenum > 0.1 THEN 'Elevated'
      END AS troponin_category
    FROM troponin_with_outcomes AS t
    WHERE t.valuenum IS NOT NULL
  ),

  -- Aggregation by category
  agg AS (
    SELECT
      troponin_category,
      COUNT(*) AS n_admissions,
      SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths
    FROM categorized
    GROUP BY troponin_category
  ),

  -- Total admissions across all categories to compute percentages
  total AS (
    SELECT SUM(n_admissions) AS total_admissions FROM agg
  )

SELECT
  a.troponin_category AS troponin_category,
  a.n_admissions AS n_admissions,
  ROUND(100.0 * a.n_admissions / t.total_admissions, 2) AS pct_of_total_admissions,
  ROUND(100.0 * a.deaths / a.n_admissions, 2) AS in_hospital_mortality_pct
FROM agg AS a
CROSS JOIN total AS t
ORDER BY
  CASE a.troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;
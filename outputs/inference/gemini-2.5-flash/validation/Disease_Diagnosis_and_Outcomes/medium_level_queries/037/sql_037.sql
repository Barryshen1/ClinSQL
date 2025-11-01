WITH
      -- Step 1: Base cohort selection (Men aged 52-62) and initial admission data
      admission_base AS (
        SELECT
          ad.subject_id,
          ad.hadm_id,
          ad.admittime,
          ad.dischtime,
          ad.hospital_expire_flag,
          ad.admission_type,
          DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
        FROM
          `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
        JOIN
          `physionet-data.mimiciv_3_1_hosp.patients` AS p
          ON ad.subject_id = p.subject_id
        WHERE
          p.gender = 'M'
          AND p.anchor_age BETWEEN 52 AND 62
      ),
      -- Step 2: Identify sepsis and septic shock diagnoses for each admission
      sepsis_flags AS (
        SELECT
          dia.hadm_id,
          -- Flag for any sepsis related ICD code
          MAX(
            CASE
              WHEN dia.icd_version = 10 AND (dia.icd_code LIKE 'A40%' OR dia.icd_code LIKE 'A41%') THEN 1
              WHEN dia.icd_version = 9 AND dia.icd_code LIKE '038%' THEN 1
              ELSE 0
            END
          ) AS has_sepsis,
          -- Flag for septic shock ICD code
          MAX(
            CASE
              WHEN dia.icd_version = 10 AND dia.icd_code = 'R65.21' THEN 1
              WHEN dia.icd_version = 9 AND dia.icd_code = '785.52' THEN 1
              ELSE 0
            END
          ) AS has_septic_shock
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
        WHERE
          -- Filter for relevant ICD codes to make the join more efficient later
          (dia.icd_version = 10 AND (dia.icd_code LIKE 'A40%' OR dia.icd_code LIKE 'A41%' OR dia.icd_code = 'R65.21'))
          OR
          (dia.icd_version = 9 AND (dia.icd_code LIKE '038%' OR dia.icd_code = '785.52'))
        GROUP BY
          dia.hadm_id
      ),
      -- Step 3: Calculate comorbidity count, excluding sepsis/shock codes
      comorbidity_counts AS (
        SELECT
          dia.hadm_id,
          COUNT(DISTINCT dia.icd_code) AS comorbidity_count
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
        WHERE
          NOT (
            (dia.icd_version = 10 AND (dia.icd_code LIKE 'A40%' OR dia.icd_code LIKE 'A41%' OR dia.icd_code = 'R65.21'))
            OR
            (dia.icd_version = 9 AND (dia.icd_code LIKE '038%' OR dia.icd_code = '785.52'))
          )
        GROUP BY
          dia.hadm_id
      )
-- Step 4: Combine all admission-level data, categorize LOS, and classify sepsis severity, then aggregate
SELECT
  cf.sepsis_severity,
  cf.los_category,
  cf.admission_type,
  -- Calculate in-hospital mortality percentage
  AVG(cf.hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  -- Calculate mean comorbidity count
  AVG(cf.comorbidity_count) AS mean_comorbidity_count
FROM
  (
    -- Subquery to select and categorize data as per the original "Step 4"
    SELECT
      ab.hadm_id, -- Keep hadm_id for joining, not strictly subject_id for final output
      ab.hospital_expire_flag,
      ab.admission_type,
      ab.los_days,
      CASE
        WHEN ab.los_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN ab.los_days BETWEEN 4 AND 7 THEN '4-7 days'
        WHEN ab.los_days >= 8 THEN '>=8 days'
        ELSE 'Unknown' -- For LOS < 1 day or other unexpected values
      END AS los_category,
      -- Classify sepsis severity based on septic shock presence
      CASE
        WHEN sf.has_septic_shock = 1 THEN 'Septic Shock'
        ELSE 'No Shock'
      END AS sepsis_severity,
      COALESCE(cc.comorbidity_count, 0) AS comorbidity_count
    FROM
      admission_base AS ab
    INNER JOIN
      sepsis_flags AS sf
      ON ab.hadm_id = sf.hadm_id
    LEFT JOIN
      comorbidity_counts AS cc
      ON ab.hadm_id = cc.hadm_id
    WHERE
      sf.has_sepsis = 1 -- Ensure only admissions with any sepsis diagnosis are included
  ) AS cf -- This aliases the subquery results
GROUP BY
  cf.sepsis_severity,
  cf.los_category,
  cf.admission_type
ORDER BY
  cf.sepsis_severity,
  cf.los_category,
  cf.admission_type;
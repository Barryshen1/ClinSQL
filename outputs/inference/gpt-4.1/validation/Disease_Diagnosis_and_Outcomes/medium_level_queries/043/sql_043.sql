WITH
-- 1. Get HF admissions for males age 44-54
hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.anchor_age BETWEEN 44 AND 54
    AND p.gender = 'M'
    AND (
      dd.long_title LIKE '%heart failure%' OR
      REGEXP_CONTAINS(dd.icd_code, r'^(I50|428)')
    )
),
-- 2. ICU flag per admission
icu_flag AS (
  SELECT DISTINCT hadm_id, 1 AS is_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
-- 3. LOS calculation and grouping
admission_los AS (
  SELECT
    h.*,
    DATETIME_DIFF(h.dischtime, h.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(h.dischtime, h.admittime, DAY) <= 7 THEN '<=7'
      ELSE '>7'
    END AS los_group,
    IFNULL(i.is_icu, 0) AS is_icu
  FROM
    hf_admissions h
    LEFT JOIN icu_flag i ON h.hadm_id = i.hadm_id
),
-- 4. Charlson index per admission (simplified, see MIT-LCP for full mapping)
charlson_map AS (
  SELECT
    hadm_id,
    SUM(
      CASE
        WHEN REGEXP_CONTAINS(icd_code, r'^(I21|410)') THEN 1 -- MI
        WHEN REGEXP_CONTAINS(icd_code, r'^(I50|428)') THEN 1 -- CHF
        WHEN REGEXP_CONTAINS(icd_code, r'^(I60|I61|I62|430|431|432)') THEN 1 -- Cerebrovascular
        WHEN REGEXP_CONTAINS(icd_code, r'^(E10|E11|250)') THEN 1 -- Diabetes
        WHEN REGEXP_CONTAINS(icd_code, r'^(C|140|141|142|143|144|145|146|147|148|149|150|151|152|153|154|155|156|157|158|159|160|161|162|163|164|165|166|167|168|169|170|171|172|173|174|175|176|177|178|179|180|181|182|183|184|185|186|187|188|189|190|191|192|193|194|195|196|197|198|199)') THEN 2 -- Malignancy
        WHEN REGEXP_CONTAINS(icd_code, r'^(N18|585)') THEN 2 -- Renal
        WHEN REGEXP_CONTAINS(icd_code, r'^(B20|042)') THEN 6 -- AIDS
        ELSE 0
      END
    ) AS charlson
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
-- 5. Add Charlson group
admission_charlson AS (
  SELECT
    a.*,
    IFNULL(c.charlson, 0) AS charlson_index,
    CASE
      WHEN IFNULL(c.charlson, 0) <= 1 THEN '0-1'
      WHEN IFNULL(c.charlson, 0) = 2 THEN '2'
      ELSE '>=3'
    END AS charlson_group
  FROM
    admission_los a
    LEFT JOIN charlson_map c ON a.hadm_id = c.hadm_id
),
-- 6. Mechanical ventilation (ICU only)
mech_vent AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (
    -- Use d_items to get itemids for ventilation, but here we use label for illustration
    -- In production, join d_items and filter for 'ventilation'
    -- For now, assume itemid for ventilation is known, e.g., 224385, 225792, etc.
    224385, 225792
  )
  UNION DISTINCT
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid IN (
    224385, 225792
  )
),
-- 7. Vasopressor use (ICU only)
vasopressor AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid IN (
    -- Vasopressor itemids: norepinephrine, epinephrine, vasopressin, dopamine, phenylephrine
    221906, 221289, 221662, 221749, 221653
  )
),
-- 8. RRT use (ICU only)
rrt AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (
    -- RRT itemids: CRRT, hemodialysis, etc.
    227558, 225810
  )
),
-- 9. Combine outcomes per admission
admission_outcomes AS (
  SELECT
    a.*,
    CASE WHEN a.is_icu = 1 AND mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent,
    CASE WHEN a.is_icu = 1 AND vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasopressor,
    CASE WHEN a.is_icu = 1 AND rrt.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt
  FROM
    admission_charlson a
    LEFT JOIN mech_vent mv ON a.hadm_id = mv.hadm_id
    LEFT JOIN vasopressor vp ON a.hadm_id = vp.hadm_id
    LEFT JOIN rrt rrt ON a.hadm_id = rrt.hadm_id
)
-- 10. Final aggregation
SELECT
  CASE WHEN is_icu = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_group,
  los_group,
  charlson_group,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
  -- Wilson score 95% CI for proportion
  ROUND(100 * (
    (SUM(hospital_expire_flag) + POWER(1.96, 2)/2) / (COUNT(*) + POWER(1.96, 2)) +
    1.96 * SQRT(
      (SUM(hospital_expire_flag) * (COUNT(*) - SUM(hospital_expire_flag)) / COUNT(*) + POWER(1.96, 2)/4)
      / (COUNT(*) + POWER(1.96, 2))
    ) / (COUNT(*) + POWER(1.96, 2))
  ), 1) AS mortality_ci_upper,
  ROUND(100 * (
    (SUM(hospital_expire_flag) + POWER(1.96, 2)/2) / (COUNT(*) + POWER(1.96, 2)) -
    1.96 * SQRT(
      (SUM(hospital_expire_flag) * (COUNT(*) - SUM(hospital_expire_flag)) / COUNT(*) + POWER(1.96, 2)/4)
      / (COUNT(*) + POWER(1.96, 2))
    ) / (COUNT(*) + POWER(1.96, 2))
  ), 1) AS mortality_ci_lower,
  ROUND(100 * SUM(mech_vent) / COUNT(*), 1) AS mech_vent_pct,
  ROUND(100 * SUM(vasopressor) / COUNT(*), 1) AS vasopressor_pct,
  ROUND(100 * SUM(rrt) / COUNT(*), 1) AS rrt_pct
FROM
  admission_outcomes
GROUP BY
  icu_group, los_group, charlson_group
ORDER BY
  icu_group, los_group, charlson_group;
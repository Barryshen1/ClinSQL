WITH hf_admissions AS (
  -- 1. Select male HF admissions age 44-54
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
       AND d.icd_version = dicd.icd_version
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%heart failure%'
    )
),

icu_flagged AS (
  -- 2. ICU vs No ICU, LOS grouping, charlson placeholder 0–1
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_flag,
    CASE
      WHEN DATE_DIFF(DATE(h.dischtime), DATE(h.admittime), DAY) <= 7 THEN '≤7'
      ELSE '>7'
    END AS los_group,
    '0–1' AS charlson_group,
    i.stay_id
  FROM hf_admissions h
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON h.subject_id = i.subject_id
   AND h.hadm_id = i.hadm_id
),

procedures_and_events AS (
  -- 3. Flag mech vent, vasopressor, RRT within the ICU stay (if any)
  SELECT
    f.icu_flag,
    f.los_group,
    f.charlson_group,
    f.hospital_expire_flag,
    MAX(IF(pe.itemid IS NOT NULL, 1, 0))    AS mech_vent_flag,
    MAX(IF(ie.subject_id IS NOT NULL, 1, 0)) AS vasopressor_flag,
    MAX(IF(pe_rrt.itemid IS NOT NULL, 1, 0)) AS rrt_flag
  FROM icu_flagged f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.subject_id = pe.subject_id
   AND f.hadm_id = pe.hadm_id
   AND f.stay_id = pe.stay_id
   -- CAST value to STRING so LOWER() works
   AND LOWER(CAST(pe.value AS STRING)) LIKE '%ventilation%'
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON f.subject_id = ie.subject_id
   AND f.hadm_id = ie.hadm_id
   AND f.stay_id = ie.stay_id
   AND LOWER(ie.ordercategoryname) LIKE '%vasopress%'
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe_rrt
    ON f.subject_id = pe_rrt.subject_id
   AND f.hadm_id = pe_rrt.hadm_id
   AND f.stay_id = pe_rrt.stay_id
   AND pe_rrt.itemid IN (225652, 225653, 225654)
  GROUP BY
    f.icu_flag,
    f.los_group,
    f.charlson_group,
    f.hospital_expire_flag
)

SELECT
  icu_flag,
  los_group,
  charlson_group,
  COUNT(*)                         AS n,
  100.0 * SUM(hospital_expire_flag) / COUNT(*)                                              AS mortality_pct,
  100.0 * (
    (p_hat + z2/(2*n) - z * SQRT((p_hat*(1-p_hat) + z2/(4*n))/n)) / (1 + z2/n)
  )                                                                                          AS mortality_ci_lower,
  100.0 * (
    (p_hat + z2/(2*n) + z * SQRT((p_hat*(1-p_hat) + z2/(4*n))/n)) / (1 + z2/n)
  )                                                                                          AS mortality_ci_upper,
  100.0 * SUM(mech_vent_flag)    / COUNT(*)                                                  AS mech_vent_pct,
  100.0 * SUM(vasopressor_flag)  / COUNT(*)                                                  AS vasopressor_pct,
  100.0 * SUM(rrt_flag)          / COUNT(*)                                                  AS rrt_pct
FROM (
  SELECT
    icu_flag,
    los_group,
    charlson_group,
    hospital_expire_flag,
    mech_vent_flag,
    vasopressor_flag,
    rrt_flag,
    COUNT(*) OVER (PARTITION BY icu_flag, los_group, charlson_group)                   AS n,
    SAFE_DIVIDE(
      SUM(hospital_expire_flag) OVER (PARTITION BY icu_flag, los_group, charlson_group),
      COUNT(*) OVER (PARTITION BY icu_flag, los_group, charlson_group)
    )                                                                                 AS p_hat,
    1.96                                                                                AS z,
    3.8416                                                                              AS z2
  FROM procedures_and_events
) sub
GROUP BY icu_flag, los_group, charlson_group, n, p_hat, z, z2
ORDER BY icu_flag, los_group, charlson_group;
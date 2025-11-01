WITH
  hemorrhagic_hadm AS (
    SELECT DISTINCT di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%hemorrhage%'
  ),
  -- Base population: male, age 40-50, ICU stays linked to admissions
  population AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      i.los AS icu_los,
      CASE
        WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1
        ELSE 0
      END AS in_hosp_mort,
      CASE
        WHEN hh.hadm_id IS NOT NULL THEN 1 ELSE 0
      END AS hemorrhagic_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON i.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON i.subject_id = p.subject_id
    LEFT JOIN hemorrhagic_hadm AS hh
      ON i.hadm_id = hh.hadm_id
    WHERE p.gender = 'Male'
      AND p.anchor_age BETWEEN 40 AND 50
  ),
  -- Diagnostic procedures within first 72 hours (using hosp.procedures_icd and d_icd_procedures)
  diag72 AS (
    SELECT i.hadm_id, COUNT(*) AS diag72_72h
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pc
      ON pc.hadm_id = i.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS di
      ON di.icd_code = pc.icd_code AND di.icd_version = pc.icd_version
    WHERE pc.chartdate BETWEEN DATE(i.intime) AND DATE_ADD(DATE(i.intime), INTERVAL 3 DAY)
      AND LOWER(di.long_title) LIKE '%diagnostic%'
    GROUP BY i.hadm_id
  ),
  -- Combine base population with diag counts (0 if no diagnostic procedures in 72h)
  combined AS (
    SELECT
      p.subject_id,
      p.hadm_id,
      p.stay_id,
      p.intime,
      p.outtime,
      p.icu_los,
      p.in_hosp_mort,
      p.hemorrhagic_flag AS hemorrhagic_indicator,
      COALESCE(d.diag72_72h, 0) AS diag72_72h
    FROM population AS p
    LEFT JOIN diag72 AS d
      ON p.hadm_id = d.hadm_id
  ),
  -- Assign group label and prepare final rows
  final AS (
    SELECT
      CASE WHEN hemorrhagic_indicator = 1 THEN 'HemorrhagicStroke'
           ELSE 'NonHemorrhagicStroke'
      END AS group_label,
      diag72_72h,
      icu_los,
      in_hosp_mort
    FROM combined
  ),
  -- Percentile / summary computations
  group_diag AS (
    SELECT group_label,
           APPROX_QUANTILES(diag72_72h, 100) AS q_diag
    FROM final
    GROUP BY group_label
  ),
  group_los AS (
    SELECT group_label,
           APPROX_QUANTILES(icu_los, 100) AS q_los
    FROM final
    GROUP BY group_label
  ),
  group_mort AS (
    SELECT group_label,
           AVG(in_hosp_mort) AS mortality_rate
    FROM final
    GROUP BY group_label
  )
SELECT
  d.group_label,
  d.q_diag[OFFSET(89)] AS p90_diag_procs,
  l.q_los[OFFSET(49)] AS median_icu_los,
  m.mortality_rate AS in_hospital_mortality_rate
FROM group_diag d
JOIN group_los l ON d.group_label = l.group_label
JOIN group_mort m ON d.group_label = m.group_label
ORDER BY group_label;
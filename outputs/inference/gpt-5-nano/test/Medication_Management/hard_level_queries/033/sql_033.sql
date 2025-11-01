WITH sepsis_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dii
    ON a.subject_id = dii.subject_id AND a.hadm_id = dii.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON dii.icd_code = did.icd_code AND dii.icd_version = did.icd_version
  WHERE LOWER(pat.gender) = 'm'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND LOWER(did.long_title) LIKE '%sepsis%'
),
qt_bleed_markers AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.admittime,
    sc.dischtime,
    sc.hospital_expire_flag,
    /* presence of QT-prolonging drugs in first 24h */
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        WHERE pr.subject_id = sc.subject_id
          AND pr.hadm_id = sc.hadm_id
          AND pr.starttime >= sc.admittime
          AND pr.starttime < TIMESTAMP_ADD(sc.admittime, INTERVAL 1 DAY)
          AND (
            LOWER(pr.drug) LIKE '%amiodarone%' OR
            LOWER(pr.drug) LIKE '%dofetilide%' OR
            LOWER(pr.drug) LIKE '%haloperidol%' OR
            LOWER(pr.drug) LIKE '%ondansetron%' OR
            LOWER(pr.drug) LIKE '%ziprasidone%' OR
            LOWER(pr.drug) LIKE '%erythromycin%' OR
            LOWER(pr.drug) LIKE '%clarithromycin%' OR
            LOWER(pr.drug) LIKE '%azithromycin%' OR
            LOWER(pr.drug) LIKE '%ciprofloxacin%' OR
            LOWER(pr.drug) LIKE '%levofloxacin%' OR
            LOWER(pr.drug) LIKE '%moxifloxacin%'
          )
      ) THEN 1 ELSE 0 END AS has_qt,
    /* presence of bleeding-risk drugs in first 24h */
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        WHERE pr.subject_id = sc.subject_id
          AND pr.hadm_id = sc.hadm_id
          AND pr.starttime >= sc.admittime
          AND pr.starttime < TIMESTAMP_ADD(sc.admittime, INTERVAL 1 DAY)
          AND (
            LOWER(pr.drug) LIKE '%warfarin%' OR
            LOWER(pr.drug) LIKE '%heparin%' OR
            LOWER(pr.drug) LIKE '%enoxaparin%' OR
            LOWER(pr.drug) LIKE '%dalteparin%' OR
            LOWER(pr.drug) LIKE '%apixaban%' OR
            LOWER(pr.drug) LIKE '%rivaroxaban%' OR
            LOWER(pr.drug) LIKE '%edoxaban%' OR
            LOWER(pr.drug) LIKE '%aspirin%' OR
            LOWER(pr.drug) LIKE '%clopidogrel%' OR
            LOWER(pr.drug) LIKE '%prasugrel%'
          )
      ) THEN 1 ELSE 0 END AS has_bleed
  FROM sepsis_cohort sc
),
mcs_calc AS (
  SELECT
    mb.subject_id,
    mb.hadm_id,
    mb.admittime,
    mb.dischtime,
    mb.hospital_expire_flag,
    mb.has_qt,
    mb.has_bleed,
    CASE
      WHEN mb.has_qt = 1 AND mb.has_bleed = 1 THEN 'both'
      ELSE 'other'
    END AS group_label,
    (
      SELECT COUNT(DISTINCT LOWER(pr.drug))
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = mb.subject_id
        AND pr.hadm_id = mb.hadm_id
        AND pr.starttime >= mb.admittime
        AND pr.starttime < TIMESTAMP_ADD(mb.admittime, INTERVAL 1 DAY)
    ) AS mcs_score
  FROM qt_bleed_markers mb
)
SELECT
  m.subject_id,
  m.hadm_id,
  a.admittime,
  a.dischtime,
  m.group_label,
  m.mcs_score,
  PERCENT_RANK() OVER (PARTITION BY m.group_label ORDER BY m.mcs_score) AS mcs_group_pct_rank,
  NTILE(4) OVER (PARTITION BY m.group_label ORDER BY m.mcs_score) AS mcs_group_quartile
FROM mcs_calc m
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
ORDER BY m.group_label, m.mcs_score;

-- Part 2: top-quartile (highest MCS) LOS and mortality
WITH sepsis_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dii
    ON a.subject_id = dii.subject_id AND a.hadm_id = dii.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON dii.icd_code = did.icd_code AND dii.icd_version = did.icd_version
  WHERE LOWER(pat.gender) = 'm'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND LOWER(did.long_title) LIKE '%sepsis%'
),
qt_bleed_markers AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.admittime,
    sc.dischtime,
    sc.hospital_expire_flag,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        WHERE pr.subject_id = sc.subject_id
          AND pr.hadm_id = sc.hadm_id
          AND pr.starttime >= sc.admittime
          AND pr.starttime < TIMESTAMP_ADD(sc.admittime, INTERVAL 1 DAY)
          AND (
            LOWER(pr.drug) LIKE '%amiodarone%' OR
            LOWER(pr.drug) LIKE '%dofetilide%' OR
            LOWER(pr.drug) LIKE '%haloperidol%' OR
            LOWER(pr.drug) LIKE '%ondansetron%' OR
            LOWER(pr.drug) LIKE '%ziprasidone%' OR
            LOWER(pr.drug) LIKE '%erythromycin%' OR
            LOWER(pr.drug) LIKE '%clarithromycin%' OR
            LOWER(pr.drug) LIKE '%azithromycin%' OR
            LOWER(pr.drug) LIKE '%ciprofloxacin%' OR
            LOWER(pr.drug) LIKE '%levofloxacin%' OR
            LOWER(pr.drug) LIKE '%moxifloxacin%'
          )
      ) THEN 1 ELSE 0 END AS has_qt,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        WHERE pr.subject_id = sc.subject_id
          AND pr.hadm_id = sc.hadm_id
          AND pr.starttime >= sc.admittime
          AND pr.starttime < TIMESTAMP_ADD(sc.admittime, INTERVAL 1 DAY)
          AND (
            LOWER(pr.drug) LIKE '%warfarin%' OR
            LOWER(pr.drug) LIKE '%heparin%' OR
            LOWER(pr.drug) LIKE '%enoxaparin%' OR
            LOWER(pr.drug) LIKE '%dalteparin%' OR
            LOWER(pr.drug) LIKE '%apixaban%' OR
            LOWER(pr.drug) LIKE '%rivaroxaban%' OR
            LOWER(pr.drug) LIKE '%edoxaban%' OR
            LOWER(pr.drug) LIKE '%aspirin%' OR
            LOWER(pr.drug) LIKE '%clopidogrel%' OR
            LOWER(pr.drug) LIKE '%prasugrel%'
          )
      ) THEN 1 ELSE 0 END AS has_bleed
  FROM sepsis_cohort sc
),
mcs_with_group AS (
  SELECT
    mb.subject_id,
    mb.hadm_id,
    mb.admittime,
    mb.dischtime,
    mb.hospital_expire_flag,
    mb.has_qt,
    mb.has_bleed,
    CASE WHEN mb.has_qt = 1 AND mb.has_bleed = 1 THEN 'both' ELSE 'other' END AS group_label,
    (
      SELECT COUNT(DISTINCT LOWER(pr2.drug))
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr2
      WHERE pr2.subject_id = mb.subject_id
        AND pr2.hadm_id = mb.hadm_id
        AND pr2.starttime >= mb.admittime
        AND pr2.starttime < TIMESTAMP_ADD(mb.admittime, INTERVAL 1 DAY)
    ) AS mcs_score
  FROM qt_bleed_markers mb
),
top_quartile AS (
  SELECT
    mws.*,
    NTILE(4) OVER (ORDER BY mws.mcs_score DESC) AS top_quart_desc
  FROM mcs_with_group mws
)
SELECT
  COUNT(*) AS n_top_quartile_admissions,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/3600) AS avg_los_hours,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_rate
FROM top_quartile tq
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON tq.subject_id = a.subject_id AND tq.hadm_id = a.hadm_id
WHERE tq.top_quart_desc = 1;
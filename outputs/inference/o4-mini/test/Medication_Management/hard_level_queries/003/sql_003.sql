WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(dd.long_title) LIKE '%status epilepticus%'
),
meds_24h AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    pr.drug
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.hadm_id = pr.hadm_id
      AND pr.starttime >= c.admittime
      AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
),
med_count AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS complexity
  FROM
    meds_24h
  GROUP BY
    hadm_id
),
interaction_group AS (
  SELECT
    mc.hadm_id,
    CASE
      WHEN SUM(IF(LOWER(m.drug) IN UNNEST([
        'amiodarone','sotalol','quinidine','dofetilide','cisapride','haloperidol'
      ]), 1, 0)) > 0 THEN 'QT'
      WHEN SUM(IF(LOWER(m.drug) IN UNNEST([
        'warfarin','heparin','dabigatran','rivaroxaban','apixaban','clopidogrel'
      ]), 1, 0)) > 0 THEN 'BLEED'
      ELSE 'GENERAL'
    END AS group_name
  FROM
    med_count mc
    JOIN meds_24h m
      USING (hadm_id)
  GROUP BY
    mc.hadm_id
),
ranked AS (
  SELECT
    c.hadm_id,
    ig.group_name,
    c.los_days,
    c.hospital_expire_flag,
    mc.complexity,
    PERCENT_RANK() OVER (
      PARTITION BY ig.group_name
      ORDER BY mc.complexity
    ) AS pct_rank
  FROM
    cohort c
    JOIN med_count mc USING (hadm_id)
    JOIN interaction_group ig USING (hadm_id)
)
SELECT
  group_name AS interaction_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(hospital_expire_flag), 3) AS mortality_rate
FROM
  ranked
WHERE
  pct_rank >= 0.75
GROUP BY
  interaction_group
ORDER BY
  interaction_group;
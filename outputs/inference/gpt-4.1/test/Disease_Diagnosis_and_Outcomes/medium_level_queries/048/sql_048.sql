WITH cohort AS (
  -- Select male patients aged 68-78 with heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (
      -- Heart failure ICD-10: I50.x; ICD-9: 428.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
      OR
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
    )
),
ckd_flags AS (
  -- Flag CKD per admission
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18'))
          OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^585'))
        THEN 1 ELSE 0
      END
    ) AS has_ckd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
dm_flags AS (
  -- Flag diabetes per admission
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[0-4]'))
          OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250'))
        THEN 1 ELSE 0
      END
    ) AS has_dm
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
final AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.anchor_age,
    c.gender,
    c.los,
    c.hospital_expire_flag,
    CASE
      WHEN c.los < 8 THEN '<8 days'
      ELSE '≥8 days'
    END AS los_group,
    IFNULL(ckd.has_ckd, 0) AS has_ckd,
    IFNULL(dm.has_dm, 0) AS has_dm
  FROM
    cohort c
    LEFT JOIN ckd_flags ckd ON c.hadm_id = ckd.hadm_id
    LEFT JOIN dm_flags dm ON c.hadm_id = dm.hadm_id
)
SELECT
  los_group,
  COUNT(*) AS n_admissions,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 1) AS mortality_percent,
  ROUND(SUM(has_ckd) * 100.0 / COUNT(*), 1) AS ckd_percent,
  ROUND(SUM(has_dm) * 100.0 / COUNT(*), 1) AS diabetes_percent
FROM
  final
GROUP BY
  los_group
ORDER BY
  los_group;
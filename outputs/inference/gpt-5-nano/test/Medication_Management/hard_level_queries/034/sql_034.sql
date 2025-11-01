WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pc
    ON pc.subject_id = a.subject_id
   AND pc.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),

med24 AS (
  -- 24h prescriptions: unique drugs and weighted high-risk classes
  SELECT
    e.subject_id,
    e.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_drug_24h,
    SUM(
      CASE
        WHEN LOWER(p.drug) LIKE '%insulin%' THEN 2.0
        WHEN LOWER(p.drug) LIKE '%heparin%' OR LOWER(p.drug) LIKE '%warfarin%' THEN 2.0
        WHEN LOWER(p.drug) LIKE '%dopamine%' OR LOWER(p.drug) LIKE '%epinephrine%' OR LOWER(p.drug) LIKE '%norepinephrine%' OR LOWER(p.drug) LIKE '%vasopressor%' THEN 1.5
        WHEN LOWER(p.drug) LIKE '%nitroglycerin%' OR LOWER(p.drug) LIKE '%vasodilator%' THEN 1.0
        ELSE 0
      END
    ) AS high_risk_weight
  FROM eligible_admissions e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.subject_id = e.subject_id
   AND p.hadm_id = e.hadm_id
  AND p.starttime >= e.admittime
  AND p.starttime <= TIMESTAMP_ADD(e.admittime, INTERVAL 1 DAY)
  GROUP BY e.subject_id, e.hadm_id
),

admission_med_complexity AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    e.deathtime,
    TIMESTAMP_DIFF(e.dischtime, e.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN e.hospital_expire_flag = 1 OR e.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS in_hospital_death,
    COALESCE(m.unique_drug_24h, 0) + COALESCE(m.high_risk_weight, 0) AS med_complexity
  FROM eligible_admissions e
  LEFT JOIN med24 m
    ON m.subject_id = e.subject_id
   AND m.hadm_id = e.hadm_id
),

readmission AS (
  -- 30-day readmission flag for admissions (based on next admission for the same subject)
  SELECT
    a.hadm_id,
    CASE
      WHEN TIMESTAMP_DIFF(LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime),
                          a.dischtime, DAY) <= 30
           AND TIMESTAMP_DIFF(LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime),
                              a.dischtime, DAY) > 0
      THEN 1
      ELSE 0
    END AS readmit_30
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
)

-- Final: attach quartile and compute metrics by quartile
SELECT
  quartile,
  COUNT(*) AS n_admissions,
  AVG(los_days) AS avg_los_days,
  AVG(in_hospital_death) * 100 AS in_hospital_mortality_pct,
  AVG(readmit_30) * 100 AS readmission_30_pct
FROM (
  SELECT
    amc.*,
    NTILE(4) OVER (ORDER BY med_complexity) AS quartile, -- stratify by med_complexity
    rm.readmit_30
  FROM admission_med_complexity AS amc
  LEFT JOIN readmission AS rm
    ON rm.hadm_id = amc.hadm_id
)
GROUP BY quartile
ORDER BY quartile;
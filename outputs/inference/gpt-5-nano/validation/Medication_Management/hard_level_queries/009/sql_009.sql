WITH eligible AS (
  -- Select female admissions aged 84-94 with AKI (ICD-10 N17% or ICD-9 584%)
  SELECT DISTINCT a.hadm_id,
                   a.subject_id,
                   a.admittime,
                   a.dischtime,
                   a.hospital_expire_flag,
                   TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/86400.0 AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND ((di.icd_version = 10 AND di.icd_code LIKE 'N17%')
         OR (di.icd_version = 9 AND di.icd_code LIKE '584%'))
),
admission_metrics AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    e.admittime,
    e.dischtime,
    e.LOS_days,
    e.hospital_expire_flag,
    -- 30-day readmission flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` b
      WHERE b.subject_id = e.subject_id
        AND b.hadm_id <> e.hadm_id
        AND b.admittime >= e.admittime
        AND b.admittime < TIMESTAMP_ADD(e.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_30d,
    -- Medication Complexity Score proxy: number of distinct drugs prescribed in this hadm
    (SELECT COUNT(DISTINCT LOWER(pr.drug))
     FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
     WHERE pr.hadm_id = e.hadm_id) AS mcs_proxy,
    -- Coadministration flags: whether there is at least one anticoagulant and at least one opioid in this hadm
    CASE
      WHEN
        ((SELECT COUNT(1)
          FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
          WHERE pr.hadm_id = e.hadm_id AND (
            LOWER(pr.drug) LIKE '%heparin%' OR LOWER(pr.drug) LIKE '%warfarin%' OR LOWER(pr.drug) LIKE '%enoxaparin%' OR
            LOWER(pr.drug) LIKE '%apixaban%' OR LOWER(pr.drug) LIKE '%rivaroxaban%' OR LOWER(pr.drug) LIKE '%edoxaban%' OR
            LOWER(pr.drug) LIKE '%dabigatran%' OR LOWER(pr.drug) LIKE '%fondaparinux%'
          )
        ) > 0)
      AND
        ((SELECT COUNT(1)
          FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` po
          WHERE po.hadm_id = e.hadm_id AND (
            LOWER(po.drug) LIKE '%morphine%' OR LOWER(po.drug) LIKE '%fentanyl%' OR LOWER(po.drug) LIKE '%hydromorphone%' OR
            LOWER(po.drug) LIKE '%oxycodone%' OR LOWER(po.drug) LIKE '%codeine%' OR LOWER(po.drug) LIKE '%meperidine%' OR LOWER(po.drug) LIKE '%tramadol%'
          )
        ) > 0)
      THEN 1 ELSE 0 END AS coadmin
  FROM eligible e
),
with_quintile AS (
  SELECT
    hadm_id,
    LOS_days AS los_days,
    hospital_expire_flag,
    readmit_30d,
    mcs_proxy,
    coadmin,
    NTILE(5) OVER (ORDER BY mcs_proxy) AS quintile
  FROM admission_metrics
)
SELECT
  quintile,
  AVG(los_days) AS avg_los_days,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS inpatient_mortality_pct,
  AVG(readmit_30d) * 100 AS thirty_day_readmit_pct,
  SUM(coadmin) AS anticoagulant_opioid_coadmin_count
FROM with_quintile
GROUP BY quintile
ORDER BY quintile;
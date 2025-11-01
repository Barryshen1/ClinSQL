WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (di.icd_code LIKE 'G41%' OR di.icd_code LIKE '345%') -- status epilepticus codes (ICD-10 and ICD-9)
),

-- 2) Medication exposure within first 24 hours: med_count_24h, QT-prolonging flag, Bleeding-risk flag
meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT ph.medication) AS med_count_24h,
    MAX(CASE
          WHEN REGEXP_CONTAINS(LOWER(ph.medication),
               '(ondansetron|ziprasidone|haloperidol|droperidol|amiodarone|quinidine|moxifloxacin|erythromycin)') THEN 1
          ELSE 0
        END) AS has_qt_prolong,
    MAX(CASE
          WHEN REGEXP_CONTAINS(LOWER(ph.medication),
               '(warfarin|heparin|enoxaparin|fondaparinux|rivaroxaban|apixaban|dabigatran|clopidogrel|aspirin)') THEN 1
          ELSE 0
        END) AS has_bleed
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.hadm_id = c.hadm_id
   AND ph.starttime >= c.admittime
   AND ph.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

-- 3) Compute percentile rank and quartile of med_count_24h per admission
quart AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag,
    m.med_count_24h,
    m.has_qt_prolong,
    m.has_bleed,
    PERCENT_RANK() OVER (ORDER BY m.med_count_24h DESC) AS med_percent_rank,
    NTILE(4) OVER (ORDER BY m.med_count_24h DESC) AS med_quartile
  FROM meds m
)

-- 4) Final aggregation on the top quartile (med_quartile = 1)
SELECT
  CASE
     WHEN has_qt_prolong = 1 THEN 'QT_prolong'
     WHEN has_bleed = 1 THEN 'Bleeding_risk'
     ELSE 'General'
  END AS group_label,
  AVG(med_percent_rank) AS avg_med_percent_rank_top_quartile,
  COUNT(*) AS n_top_quartile,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS avg_los_days,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS mortality_rate
FROM quart
WHERE med_quartile = 1
GROUP BY group_label
ORDER BY group_label;
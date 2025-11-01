WITH aki_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id,
         a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
      OR (di.icd_version = 9  AND di.icd_code LIKE '584%')
    )
),

meds AS (
  SELECT hadm_id, subject_id,
         LOWER(CAST(drug AS STRING)) AS med
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM aki_admissions)
  UNION ALL
  SELECT hadm_id, subject_id,
         LOWER(CAST(medication AS STRING)) AS med
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE hadm_id IN (SELECT hadm_id FROM aki_admissions)
),

med_class AS (
  SELECT
    m.hadm_id,
    m.subject_id,
    m.med,
    CASE WHEN REGEXP_CONTAINS(med, r'(?i)(benzodiazepine|benzo|lorazepam|diazepam|midazolam|alprazolam|clonazepam|phenobarbital|fentanyl|morphine|hydromorphone|oxycodone|codeine|propofol|sedative|hypnotic)') THEN 1 ELSE 0 END AS is_cns,
    CASE WHEN REGEXP_CONTAINS(med, r'(?i)(gentamicin|tobramycin|amikacin|vancomycin|amphotericin|iohexol|iothalamate|cisplatin|carboplatin|contrast|nephrotoxic)') THEN 1 ELSE 0 END AS is_nephro
  FROM meds AS m
),

med_counts AS (
  SELECT hadm_id,
         COUNT(DISTINCT CASE WHEN is_cns = 1 THEN med END) AS cns_count,
         COUNT(DISTINCT CASE WHEN is_nephro = 1 THEN med END) AS nephro_count
  FROM med_class
  GROUP BY hadm_id
),

mcs_per_adm AS (
  SELECT a.hadm_id, a.subject_id,
         a.admittime, a.dischtime,
         a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days,
         COALESCE(mc.cns_count, 0) AS cns_count,
         COALESCE(mc.nephro_count, 0) AS nephro_count,
         (COALESCE(mc.cns_count, 0) + COALESCE(mc.nephro_count, 0)) AS mcs,
         CASE WHEN COALESCE(mc.cns_count, 0) > 0 AND COALESCE(mc.nephro_count, 0) > 0 THEN 1 ELSE 0 END AS has_both
  FROM aki_admissions AS a
  LEFT JOIN med_counts AS mc
    ON a.hadm_id = mc.hadm_id
),

group_data AS (
  SELECT hadm_id, subject_id, LOS_days, hospital_expire_flag, mcs,
         CASE WHEN has_both = 1 THEN 'Both CNS and Nephro' ELSE 'Other AKI' END AS group_label
  FROM mcs_per_adm
)

-- Part 7: Per-group MCS quintile/median and mean metrics
, mcs_quartiles AS (
  SELECT group_label,
         APPROX_QUANTILES(mcs, 4) AS mcs_q,
         AVG(mcs) AS mean_mcs,
         AVG(LOS_days) AS mean_los_days,
         AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM group_data
  GROUP BY group_label
),

stats AS (
  SELECT group_label,
         mcs_q[OFFSET(1)] AS mcs_q1,   -- 25th percentile
         mcs_q[OFFSET(2)] AS mcs_median, -- median
         mcs_q[OFFSET(3)] AS mcs_q3,   -- 75th percentile
         mean_mcs,
         mean_los_days,
         mortality_rate
  FROM mcs_quartiles
)

-- Part 8: Top-quartile (LOS) metrics per group
, los_q3 AS (
  SELECT group_label,
         (APPROX_QUANTILES(LOS_days, 4))[OFFSET(3)] AS los_q3
  FROM group_data
  GROUP BY group_label
),
top_quartile AS (
  SELECT g.group_label,
         AVG(g.LOS_days) AS mean_los_top_quartile,
         AVG(CAST(g.hospital_expire_flag AS FLOAT64)) AS mortality_top_quartile
  FROM group_data AS g
  JOIN los_q3 AS l
    ON g.group_label = l.group_label
  WHERE g.LOS_days >= l.los_q3
  GROUP BY g.group_label
)

-- Part 9: Final output
SELECT
  s.group_label,
  s.mcs_q1 AS mcs_quartile_25,
  s.mcs_median AS mcs_median,
  s.mcs_q3 AS mcs_quartile_75,
  s.mean_mcs,
  s.mean_los_days,
  s.mortality_rate,
  t.mean_los_top_quartile,
  t.mortality_top_quartile
FROM stats AS s
LEFT JOIN top_quartile AS t
  ON s.group_label = t.group_label
ORDER BY s.group_label;
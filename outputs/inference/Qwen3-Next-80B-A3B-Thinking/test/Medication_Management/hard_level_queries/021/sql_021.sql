WITH eligible_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.hadm_id = adm.hadm_id
        AND le.itemid = 51300
        AND le.valuenum < 1500
    ) AS has_neutropenia,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.hadm_id = adm.hadm_id
        AND ce.itemid = 223761
        AND ce.valuenum > 38.0
    ) AS has_fever
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 41 AND 51
),
medication_counts AS (
  SELECT
    adm.hadm_id,
    COUNT(DISTINCT pres.drug) AS unique_med_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON adm.hadm_id = pres.hadm_id
  WHERE pres.starttime BETWEEN adm.admittime AND adm.admittime + INTERVAL 48 HOUR
  GROUP BY adm.hadm_id
),
eligible_with_med_count AS (
  SELECT
    ea.subject_id,
    ea.hadm_id,
    ea.admittime,
    ea.dischtime,
    ea.hospital_expire_flag,
    mc.unique_med_count,
    DATE_DIFF(ea.dischtime, ea.admittime, DAY) AS los_days
  FROM eligible_admissions ea
  JOIN medication_counts mc
    ON ea.hadm_id = mc.hadm_id
  WHERE ea.has_neutropenia AND ea.has_fever
),
readmissions AS (
  SELECT
    adm1.hadm_id,
    MAX(CASE WHEN adm2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm2
    ON adm1.subject_id = adm2.subject_id
    AND adm2.admittime > adm1.dischtime
    AND adm2.admittime <= adm1.dischtime + INTERVAL 30 DAY
  GROUP BY adm1.hadm_id
),
final_data AS (
  SELECT
    ewmc.*,
    COALESCE(r.readmitted_30d, 0) AS readmitted_30d
  FROM eligible_with_med_count ewmc
  LEFT JOIN readmissions r
    ON ewmc.hadm_id = r.hadm_id
),
tertile_data AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY unique_med_count) AS tertile
  FROM final_data
)
SELECT
  tertile,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(readmitted_30d) * 100 AS readmission_30d_pct
FROM tertile_data
GROUP BY tertile
ORDER BY tertile;
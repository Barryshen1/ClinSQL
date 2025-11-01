WITH pneumonia_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
med_counts AS (
  SELECT
    p.hadm_id,
    p.subject_id,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    p.deathtime,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM pneumonia_population AS p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = p.subject_id
   AND pr.hadm_id = p.hadm_id
   AND pr.starttime >= p.admittime
   AND pr.starttime < TIMESTAMP_ADD(p.admittime, INTERVAL 7 DAY)
  GROUP BY
    p.hadm_id,
    p.subject_id,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    p.deathtime
),
final_source AS (
  SELECT
    mc.hadm_id,
    mc.subject_id,
    mc.admittime,
    mc.dischtime,
    mc.hospital_expire_flag,
    mc.deathtime,
    mc.med_count,
    NTILE(3) OVER (ORDER BY mc.med_count) AS tertile,
    CASE
      WHEN mc.hospital_expire_flag = 1 OR mc.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS in_hosp_mort,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE a2.subject_id = mc.subject_id
          AND a2.dischtime IS NOT NULL
          AND a2.admittime > mc.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(mc.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30
  FROM med_counts AS mc
)
SELECT
  tertile AS tertile_group,
  COUNT(*) AS admissions,
  MIN(med_count) AS min_score,
  AVG(med_count) AS avg_score,
  MAX(med_count) AS max_score,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los,
  100.0 * SUM(in_hosp_mort) / COUNT(*) AS in_hospital_mortality_pct,
  100.0 * SUM(readmit_30) / COUNT(*) AS readmission_30d_pct
FROM final_source
GROUP BY tertile
ORDER BY tertile;
WITH pneumonia_adm AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.subject_id = di.subject_id
    AND adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code
    AND di.icd_version = ddi.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND LOWER(ddi.long_title) LIKE '%pneumonia%'
),
complexity AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    COUNT(DISTINCT LOWER(pr.drug)) AS complexity
  FROM pneumonia_adm pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pa.subject_id = pr.subject_id
    AND pa.hadm_id = pr.hadm_id
    AND pr.starttime >= pa.admittime
    AND pr.starttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 7 DAY)
  GROUP BY pa.subject_id, pa.hadm_id
),
readmit_flag AS (
  SELECT
    subject_id,
    hadm_id,
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
final AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    c.complexity,
    TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    pa.hospital_expire_flag,
    CASE
      WHEN rf.next_admittime IS NOT NULL
       AND TIMESTAMP_DIFF(rf.next_admittime, pa.dischtime, DAY) <= 30
       AND TIMESTAMP_DIFF(rf.next_admittime, pa.dischtime, DAY) >= 0
      THEN 1 ELSE 0
    END AS readmit30
  FROM pneumonia_adm pa
  JOIN complexity c
    ON pa.subject_id = c.subject_id AND pa.hadm_id = c.hadm_id
  JOIN readmit_flag rf
    ON pa.subject_id = rf.subject_id AND pa.hadm_id = rf.hadm_id
),
with_tertile AS (
  SELECT *,
         NTILE(3) OVER (ORDER BY complexity) AS tertile
  FROM final
)
SELECT
  tertile,
  COUNT(*) AS admission_count,
  MIN(complexity) AS min_complexity,
  AVG(complexity) AS avg_complexity,
  MAX(complexity) AS max_complexity,
  AVG(los_days) AS mean_los_days,
  100 * SUM(hospital_expire_flag)/COUNT(*) AS in_hospital_mortality_pct,
  100 * SUM(readmit30)/COUNT(*) AS readmit30_pct
FROM with_tertile
GROUP BY tertile
ORDER BY tertile;
WITH HF_adm AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         a.hospital_expire_flag, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND ( (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') )
),

comorb AS (
  -- comorbidity burden: number of non-HF diagnoses per admission
  SELECT h.subject_id, h.hadm_id,
         COUNT(DISTINCT CASE
                          WHEN NOT ((d.icd_version = 9 AND d.icd_code LIKE '428%')
                                        OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%'))
                          THEN d.icd_code
                        END) AS comorbidity_count
  FROM HF_adm h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = h.subject_id AND d.hadm_id = h.hadm_id
  GROUP BY h.subject_id, h.hadm_id
),

ckd_diab AS (
  -- CKD and diabetes presence across all diagnoses for the admission
  SELECT h.subject_id, h.hadm_id,
         MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%')
                   OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
                   THEN 1 ELSE 0 END) AS ckdpresent,
         MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%')
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%'))
                   THEN 1 ELSE 0 END) AS diabetes_present
  FROM HF_adm h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = h.subject_id AND d.hadm_id = h.hadm_id
  GROUP BY h.subject_id, h.hadm_id
),

base AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality,
         c.comorbidity_count,
         ck.ckdpresent,
         ck.diabetes_present
  FROM HF_adm a
  JOIN comorb c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  JOIN ckd_diab ck ON a.subject_id = ck.subject_id AND a.hadm_id = ck.hadm_id
),

t AS (
  SELECT *,
         NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile
  FROM base
)

SELECT
  CASE WHEN los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group_label,
  CASE comorbidity_tertile
     WHEN 1 THEN 'Low'
     WHEN 2 THEN 'Med'
     WHEN 3 THEN 'High'
  END AS comorbidity_tertile_label,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(mortality) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(ckdpresent) / COUNT(*), 2) AS CKD_prevalence_pct,
  ROUND(100.0 * SUM(diabetes_present) / COUNT(*), 2) AS Diabetes_prevalence_pct
FROM t
GROUP BY los_group_label, comorbidity_tertile_label
ORDER BY los_group_label, comorbidity_tertile_label;
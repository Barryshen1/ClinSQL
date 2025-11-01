WITH cohort AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = h.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS care_setting,
    MAX(TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY)) AS los_days,
    MAX(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hosp_death,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count,
    MAX(
      CASE
        WHEN LOWER(ld.long_title) LIKE '%postoperative%'
             OR LOWER(ld.long_title) LIKE '%post op%'
             OR LOWER(ld.long_title) LIKE '%postoperative%'
        THEN 1 ELSE 0
      END
    ) AS postop_comp
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = h.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = h.subject_id
   AND d.hadm_id = h.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ld
    ON ld.icd_code = d.icd_code
   AND ld.icd_version = d.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 82 AND 92
  GROUP BY h.subject_id, h.hadm_id
)
SELECT
  care_setting AS setting,
  CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS los_group,
  CASE
    WHEN comorbidity_count <= 1 THEN '0-1'
    WHEN comorbidity_count = 2 THEN '2'
    ELSE '>=3'
  END AS comorb_bin,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(in_hosp_death) / COUNT(*), 2) AS in_hospital_mortality_pct,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM cohort
WHERE postop_comp = 1
GROUP BY setting, los_group, comorb_bin
ORDER BY setting, los_group, comorb_bin;
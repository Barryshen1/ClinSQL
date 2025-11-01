WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 64 AND 74
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code IN ('0380','0381','03810','03811','03812','03819','0382','0383','03840','03841','03842','03843','03844','03849','0388','0389','99591','99592'))
        OR (icd_version = 10 AND icd_code IN ('A400','A401','A402','A403','A408','A409','A410','A411','A412','A413','A414','A4150','A4151','A4152','A4159','A418','A419','R6520'))
    )
    AND adm.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code = '78552')
        OR (icd_version = 10 AND icd_code = 'R6521')
    )
),

cohort_quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM cohort
),

ckd AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(585|586|V42|V45|V56|403|404)'))
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(N18|N19|I12|I13|Z49|Z94|Z99|N25)'))
),

diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%')
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(E10|E11|E12|E13|E14)'))
)

SELECT 
  los_quartile,
 100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate_percent,
  COUNT(*) AS total_admissions,
  100.0 * SUM(CASE WHEN ckd.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS ckd_prevalence_percent,
  100.0 * SUM(CASE WHEN diabetes.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS diabetes_prevalence_percent
FROM cohort_quartiles cq
LEFT JOIN ckd 
  ON cq.hadm_id = ckd.hadm_id
LEFT JOIN diabetes 
  ON cq.hadm_id = diabetes.hadm_id
GROUP BY los_quartile
ORDER BY los_quartile;
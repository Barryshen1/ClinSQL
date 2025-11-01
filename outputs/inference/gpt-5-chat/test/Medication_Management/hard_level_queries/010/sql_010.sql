WITH hemorrhagic_stroke_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender,
                  adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
    ON dx.icd_code = dxd.icd_code
    AND dx.icd_version = dxd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 61 AND 71
    AND dx.icd_version = 10
    AND (dx.icd_code LIKE 'I60%' OR dx.icd_code LIKE 'I61%' OR dx.icd_code LIKE 'I62%')
),
complexity AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(DISTINCT pr.drug) AS complexity_score
  FROM hemorrhagic_stroke_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
los_calc AS (
  SELECT subject_id, hadm_id,
         TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM hemorrhagic_stroke_cohort
),
readmission_flag AS (
  SELECT a.subject_id, a.hadm_id,
         CASE WHEN MIN(b.admittime) IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM hemorrhagic_stroke_cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` b
    ON a.subject_id = b.subject_id
    AND b.hadm_id != a.hadm_id
    AND b.admittime > a.dischtime
    AND b.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
  GROUP BY a.subject_id, a.hadm_id
),
all_metrics AS (
  SELECT c.subject_id, c.hadm_id,
         complexity.complexity_score,
         los_calc.los_days,
         c.hospital_expire_flag,
         readmission_flag.readmit_30d
  FROM hemorrhagic_stroke_cohort c
  JOIN complexity
    ON c.subject_id = complexity.subject_id AND c.hadm_id = complexity.hadm_id
  JOIN los_calc
    ON c.subject_id = los_calc.subject_id AND c.hadm_id = los_calc.hadm_id
  JOIN readmission_flag
    ON c.subject_id = readmission_flag.subject_id AND c.hadm_id = readmission_flag.hadm_id
),
with_quintile AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM all_metrics
)
SELECT quintile,
       COUNT(DISTINCT subject_id) AS num_patients,
       AVG(complexity_score) AS mean_complexity_score,
       AVG(los_days) AS avg_los_days,
       AVG(hospital_expire_flag) AS in_hosp_mortality_rate,
       AVG(readmit_30d) AS readmit_30d_rate
FROM with_quintile
GROUP BY quintile
ORDER BY quintile;
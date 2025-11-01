WITH hemorrhagic_stroke_adm AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 89 AND 99
    AND (
      LOWER(dd.long_title) LIKE '%hemorrhage%' AND (
        LOWER(dd.long_title) LIKE '%cerebr%' OR
        LOWER(dd.long_title) LIKE '%subarachnoid%' OR
        LOWER(dd.long_title) LIKE '%intracerebr%'
      )
    )
),
complexity AS (
  SELECT hsa.subject_id, hsa.hadm_id,
         COUNT(DISTINCT pr.drug) AS unique_drug_count
  FROM hemorrhagic_stroke_adm hsa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON hsa.subject_id = pr.subject_id AND hsa.hadm_id = pr.hadm_id
  WHERE pr.starttime >= hsa.admittime
    AND pr.starttime < DATETIME_ADD(hsa.admittime, INTERVAL 7 DAY)
    AND pr.drug IS NOT NULL
  GROUP BY hsa.subject_id, hsa.hadm_id
),
quintiled AS (
  SELECT hsa.subject_id, hsa.hadm_id, hsa.admittime, hsa.dischtime,
         hsa.hospital_expire_flag,
         c.unique_drug_count,
         NTILE(5) OVER (ORDER BY c.unique_drug_count) AS complexity_quintile,
         DATETIME_DIFF(hsa.dischtime, hsa.admittime, DAY) AS los
  FROM hemorrhagic_stroke_adm hsa
  JOIN complexity c
    ON hsa.subject_id = c.subject_id AND hsa.hadm_id = c.hadm_id
),
readmission AS (
  SELECT q.subject_id, q.hadm_id,
         CASE WHEN COUNT(ra.hadm_id) > 0 THEN 1 ELSE 0 END AS readmit_30d
  FROM quintiled q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ra
    ON q.subject_id = ra.subject_id
    AND ra.admittime > q.dischtime
    AND DATETIME_DIFF(ra.admittime, q.dischtime, DAY) <= 30
  GROUP BY q.subject_id, q.hadm_id
)
SELECT q.complexity_quintile,
       AVG(q.los) AS avg_los_days,
       AVG(q.hospital_expire_flag) AS inpatient_mortality_rate,
       AVG(r.readmit_30d) AS readmit_30d_rate
FROM quintiled q
JOIN readmission r
  ON q.subject_id = r.subject_id AND q.hadm_id = r.hadm_id
GROUP BY q.complexity_quintile
ORDER BY q.complexity_quintile;
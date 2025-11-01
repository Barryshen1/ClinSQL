WITH stroke_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 89 AND 99
    AND REGEXP_CONTAINS(d.icd_code, r'^I6[0-2]')
  QUALIFY ROW_NUMBER() OVER(PARTITION BY adm.hadm_id ORDER BY diag.seq_num) = 1
),

drug_counts AS (
  SELECT 
    sa.hadm_id,
    COUNT(DISTINCT pr.drug) AS num_drugs
  FROM stroke_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON sa.hadm_id = pr.hadm_id
  WHERE DATETIME_DIFF(pr.starttime, sa.admittime, HOUR) BETWEEN 0 AND 168  -- 7 days = 168 hours
  GROUP BY sa.hadm_id
),

quintiles AS (
  SELECT 
    hadm_id,
    num_drugs,
    NTILE(5) OVER (ORDER BY num_drugs) AS quintile
  FROM drug_counts
),

readmissions AS (
  SELECT 
    sa.hadm_id,
    MAX(
      CASE WHEN readm.admittime > sa.dischtime 
           AND DATETIME_DIFF(readm.admittime, sa.dischtime, DAY) <= 30 
           THEN 1 ELSE 0 
      END
    ) AS readmit_30day
  FROM stroke_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` readm
    ON sa.subject_id = readm.subject_id
    AND readm.admittime != sa.admittime  -- exclude the index admission
  WHERE sa.hospital_expire_flag = 0
  GROUP BY sa.hadm_id
)

SELECT 
  q.quintile,
  COUNT(*) AS n_admissions,
  AVG(sa.los) AS avg_los,
  AVG(sa.hospital_expire_flag) * 100 AS mortality_percent,
  AVG(COALESCE(r.readmit_30day, 0)) * 100 AS readmit_30day_percent
FROM stroke_admissions sa
INNER JOIN quintiles q
  ON sa.hadm_id = q.hadm_id
LEFT JOIN readmissions r
  ON sa.hadm_id = r.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;
WITH hepatic_failure_adm AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'K72%')
      OR (d.icd_version = 9 AND d.icd_code IN ('570','5722','5723','5724','5728'))
    )
),
meds_first72 AS (
  SELECT ha.subject_id, ha.hadm_id,
         COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM hepatic_failure_adm ha
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ha.subject_id = pr.subject_id
   AND ha.hadm_id = pr.hadm_id
   AND pr.starttime IS NOT NULL
   AND pr.starttime <= DATETIME_ADD(ha.admittime, INTERVAL 72 HOUR)
  GROUP BY ha.subject_id, ha.hadm_id
),
scored AS (
  SELECT ha.*, 
         COALESCE(m.med_complexity_score,0) AS score
  FROM hepatic_failure_adm ha
  LEFT JOIN meds_first72 m
    ON ha.subject_id = m.subject_id AND ha.hadm_id = m.hadm_id
),
with_quintile AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY score) AS quintile,
         TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0 AS los_days
  FROM scored
),
-- flag readmission within 30 days
readmit AS (
  SELECT curr.subject_id, curr.hadm_id,
         CASE WHEN MIN(TIMESTAMP_DIFF(next.admittime, curr.dischtime, DAY)) <= 30
                  AND MIN(TIMESTAMP_DIFF(next.admittime, curr.dischtime, DAY)) IS NOT NULL
              THEN 1 ELSE 0 END AS readmit_30d
  FROM with_quintile curr
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON curr.subject_id = next.subject_id
   AND curr.hadm_id != next.hadm_id
   AND next.admittime > curr.dischtime
   AND TIMESTAMP_DIFF(next.admittime, curr.dischtime, DAY) <= 30
  GROUP BY curr.subject_id, curr.hadm_id
)
SELECT w.quintile,
       COUNT(*) AS n_admissions,
       MIN(w.score) AS min_score,
       MAX(w.score) AS max_score,
       ROUND(AVG(w.score),2) AS mean_score,
       ROUND(AVG(w.los_days),2) AS mean_los_days,
       ROUND(100*AVG(w.hospital_expire_flag),1) AS in_hosp_mortality_pct,
       ROUND(100*AVG(r.readmit_30d),1) AS readmit_30d_pct
FROM with_quintile w
JOIN readmit r
  ON w.subject_id = r.subject_id AND w.hadm_id = r.hadm_id
GROUP BY quintile
ORDER BY quintile;
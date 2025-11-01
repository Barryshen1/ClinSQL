WITH Cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dtd
    ON dtd.subject_id = a.subject_id AND dtd.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS t2
    ON t2.icd_code = dtd.icd_code AND t2.icd_version = dtd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dfh
    ON dfh.subject_id = a.subject_id AND dfh.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS hf
    ON hf.icd_code = dfh.icd_code AND hf.icd_version = dfh.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (LOWER(t2.long_title) LIKE '%type 2 diabetes%' OR LOWER(t2.long_title) LIKE '%diabetes mellitus type 2%')
    AND (LOWER(hf.long_title) LIKE '%heart failure%' OR LOWER(hf.long_title) LIKE '%congestive heart failure%')
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
W1_Bools AS (
  SELECT c.hadm_id,
         MAX(CASE WHEN LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%basal%' OR
                       LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%basal%' THEN 1 ELSE 0 END) AS has_basal,
         MAX(CASE WHEN LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%bolus%' OR
                       LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%bolus%' THEN 1 ELSE 0 END) AS has_bolus,
         MAX(CASE WHEN LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%sliding%' OR
                       LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%sliding-scale%' OR
                       LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%sliding-scale%' OR
                       LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%sliding scale%' THEN 1 ELSE 0 END) AS has_ssi
  FROM Cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS i
    ON i.hadm_id = c.hadm_id
   AND i.starttime >= c.admittime
   AND i.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 H)
  WHERE LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%insulin%' OR LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%insulin%'
  GROUP BY c.hadm_id
),
W1_Regimen AS (
  SELECT hadm_id,
         CASE
           WHEN has_basal = 1 AND has_bolus = 1 THEN 'basal-bolus'
           WHEN has_ssi = 1 THEN 'sliding-scale'
           WHEN has_basal = 1 THEN 'basal'
           WHEN has_bolus = 1 THEN 'bolus'
           ELSE NULL
         END AS regimen
  FROM W1_Bools
),
W2_Bools AS (
  SELECT c.hadm_id,
         MAX(CASE WHEN LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%basal%' OR
                       LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%basal%' THEN 1 ELSE 0 END) AS has_basal,
         MAX(CASE WHEN LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%bolus%' OR
                       LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%bolus%' THEN 1 ELSE 0 END) AS has_bolus,
         MAX(CASE WHEN LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%sliding%' OR
                       LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%sliding-scale%' OR
                       LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%sliding-scale%' OR
                       LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%sliding scale%' THEN 1 ELSE 0 END) AS has_ssi
  FROM Cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS i
    ON i.hadm_id = c.hadm_id
   AND i.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 H)
   AND i.starttime <= c.dischtime
  WHERE LOWER(COALESCE(i.ordercategoryname,'')) LIKE '%insulin%' OR LOWER(COALESCE(i.ordercategorydescription,'')) LIKE '%insulin%'
  GROUP BY c.hadm_id
),
W2_Regimen AS (
  SELECT hadm_id,
         CASE
           WHEN has_basal = 1 AND has_bolus = 1 THEN 'basal-bolus'
           WHEN has_ssi = 1 THEN 'sliding-scale'
           WHEN has_basal = 1 THEN 'basal'
           WHEN has_bolus = 1 THEN 'bolus'
           ELSE NULL
         END AS regimen
  FROM W2_Bools
),
Totals AS (
  SELECT COUNT(*) AS total FROM Cohort
),
Final AS (
  SELECT reg.regimen,
         COALESCE(w1.count1, 0) AS count_first72,
         COALESCE(w2.count2, 0) AS count_final48
  FROM (SELECT 'basal' AS regimen UNION ALL SELECT 'bolus' UNION ALL SELECT 'basal-bolus' UNION ALL SELECT 'sliding-scale') AS reg
  LEFT JOIN (
     SELECT regimen, COUNT(*) AS count1
     FROM W1_Regimen
     WHERE regimen IS NOT NULL
     GROUP BY regimen
  ) AS w1 ON w1.regimen = reg.regimen
  LEFT JOIN (
     SELECT regimen, COUNT(*) AS count2
     FROM W2_Regimen
     WHERE regimen IS NOT NULL
     GROUP BY regimen
  ) AS w2 ON w2.regimen = reg.regimen
),
FinalOutput AS (
  SELECT f.regimen,
         f.count_first72,
         f.count_final48,
         t.total
  FROM Final f CROSS JOIN Totals t
)
SELECT regimen,
       ROUND(100.0 * count_first72 / total, 2) AS pct_first72,
       ROUND(100.0 * count_final48 / total, 2) AS pct_final48,
       ROUND(ABS(count_first72 - count_final48) * 100.0 / total, 2) AS diff_percentage_points
FROM FinalOutput
ORDER BY regimen;
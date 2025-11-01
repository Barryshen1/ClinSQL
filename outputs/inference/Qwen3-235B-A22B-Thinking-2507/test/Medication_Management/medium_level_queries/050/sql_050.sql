WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime AS window1_start,
    LEAST(a.admittime + INTERVAL '24' HOUR, a.dischtime) AS window1_end,
    GREATEST(a.dischtime - INTERVAL '48' HOUR, a.admittime) AS window2_start,
    a.dischtime AS window2_end
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I50%'
    )
),
med_flags AS (
  SELECT 
    c.hadm_id,
    -- Antidiabetic
    MAX(CASE WHEN e.charttime >= c.window1_start AND e.charttime <= c.window1_end 
              AND (LOWER(e.medication) LIKE '%insulin%' OR
                   LOWER(e.medication) LIKE '%metformin%' OR
                   LOWER(e.medication) LIKE '%glipizide%' OR
                   LOWER(e.medication) LIKE '%glyburide%' OR
                   LOWER(e.medication) LIKE '%sitagliptin%' OR
                   LOWER(e.medication) LIKE '%saxagliptin%' OR
                   LOWER(e.medication) LIKE '%linagliptin%' OR
                   LOWER(e.medication) LIKE '%alogliptin%' OR
                   LOWER(e.medication) LIKE '%exenatide%' OR
                   LOWER(e.medication) LIKE '%liraglutide%' OR
                   LOWER(e.medication) LIKE '%dulaglutide%' OR
                   LOWER(e.medication) LIKE '%semaglutide%' OR
                   LOWER(e.medication) LIKE '%canagliflozin%' OR
                   LOWER(e.medication) LIKE '%dapagliflozin%' OR
                   LOWER(e.medication) LIKE '%empagliflozin%' OR
                   LOWER(e.medication) LIKE '%ertugliflozin%' OR
                   LOWER(e.medication) LIKE '%pioglitazone%' OR
                   LOWER(e.medication) LIKE '%rosiglitazone%' OR
                   LOWER(e.medication) LIKE '%acarbose%' OR
                   LOWER(e.medication) LIKE '%miglitol%' OR
                   LOWER(e.medication) LIKE '%repaglinide%' OR
                   LOWER(e.medication) LIKE '%nateglinide%')
             THEN 1 ELSE 0 END) AS antidiabetic_window1,
    MAX(CASE WHEN e.charttime >= c.window2_start AND e.charttime <= c.window2_end 
              AND (LOWER(e.medication) LIKE '%insulin%' OR
                   LOWER(e.medication) LIKE '%metformin%' OR
                   LOWER(e.medication) LIKE '%glipizide%' OR
                   LOWER(e.medication) LIKE '%glyburide%' OR
                   LOWER(e.medication) LIKE '%sitagliptin%' OR
                   LOWER(e.medication) LIKE '%saxagliptin%' OR
                   LOWER(e.medication) LIKE '%linagliptin%' OR
                   LOWER(e.medication) LIKE '%alogliptin%' OR
                   LOWER(e.medication) LIKE '%exenatide%' OR
                   LOWER(e.medication) LIKE '%liraglutide%' OR
                   LOWER(e.medication) LIKE '%dulaglutide%' OR
                   LOWER(e.medication) LIKE '%semaglutide%' OR
                   LOWER(e.medication) LIKE '%canagliflozin%' OR
                   LOWER(e.medication) LIKE '%dapagliflozin%' OR
                   LOWER(e.medication) LIKE '%empagliflozin%' OR
                   LOWER(e.medication) LIKE '%ertugliflozin%' OR
                   LOWER(e.medication) LIKE '%pioglitazone%' OR
                   LOWER(e.medication) LIKE '%rosiglitazone%' OR
                   LOWER(e.medication) LIKE '%acarbose%' OR
                   LOWER(e.medication) LIKE '%miglitol%' OR
                   LOWER(e.medication) LIKE '%repaglinide%' OR
                   LOWER(e.medication) LIKE '%nateglinide%')
             THEN 1 ELSE 0 END) AS antidiabetic_window2,
    -- Beta-Blocker
    MAX(CASE WHEN e.charttime >= c.window1_start AND e.charttime <= c.window1_end 
              AND (LOWER(e.medication) LIKE '%metoprolol%' OR
                   LOWER(e.medication) LIKE '%atenolol%' OR
                   LOWER(e.medication) LIKE '%propranolol%' OR
                   LOWER(e.medication) LIKE '%carvedilol%' OR
                   LOWER(e.medication) LIKE '%bisoprolol%' OR
                   LOWER(e.medication) LIKE '%nadolol%' OR
                   LOWER(e.medication) LIKE '%timolol%' OR
                   LOWER(e.medication) LIKE '%labetalol%' OR
                   LOWER(e.medication) LIKE '%nebivolol%' OR
                   LOWER(e.medication) LIKE '%sotalol%')
             THEN 1 ELSE 0 END) AS beta_blocker_window1,
    MAX(CASE WHEN e.charttime >= c.window2_start AND e.charttime <= c.window2_end 
              AND (LOWER(e.medication) LIKE '%metoprolol%' OR
                   LOWER(e.medication) LIKE '%atenolol%' OR
                   LOWER(e.medication) LIKE '%propranolol%' OR
                   LOWER(e.medication) LIKE '%carvedilol%' OR
                   LOWER(e.medication) LIKE '%bisoprolol%' OR
                   LOWER(e.medication) LIKE '%nadolol%' OR
                   LOWER(e.medication) LIKE '%timolol%' OR
                   LOWER(e.medication) LIKE '%labetalol%' OR
                   LOWER(e.medication) LIKE '%nebivolol%' OR
                   LOWER(e.medication) LIKE '%sotalol%')
             THEN 1 ELSE 0 END) AS beta_blocker_window2,
    -- ACEi/ARB/ARNI
    MAX(CASE WHEN e.charttime >= c.window1_start AND e.charttime <= c.window1_end 
              AND (LOWER(e.medication) LIKE '%lisinopril%' OR
                   LOWER(e.medication) LIKE '%enalapril%' OR
                   LOWER(e.medication) LIKE '%ramipril%' OR
                   LOWER(e.medication) LIKE '%benazepril%' OR
                   LOWER(e.medication) LIKE '%captopril%' OR
                   LOWER(e.medication) LIKE '%fosinopril%' OR
                   LOWER(e.medication) LIKE '%moexipril%' OR
                   LOWER(e.medication) LIKE '%perindopril%' OR
                   LOWER(e.medication) LIKE '%quinapril%' OR
                   LOWER(e.medication) LIKE '%trandolapril%' OR
                   LOWER(e.medication) LIKE '%losartan%' OR
                   LOWER(e.medication) LIKE '%valsartan%' OR
                   LOWER(e.medication) LIKE '%irbesartan%' OR
                   LOWER(e.medication) LIKE '%candesartan%' OR
                   LOWER(e.medication) LIKE '%telmisartan%' OR
                   LOWER(e.medication) LIKE '%olmesartan%' OR
                   LOWER(e.medication) LIKE '%eprosartan%' OR
                   LOWER(e.medication) LIKE '%sacubitril%' OR
                   LOWER(e.medication) LIKE '%entresto%')
             THEN 1 ELSE 0 END) AS ace_arni_window1,
    MAX(CASE WHEN e.charttime >= c.window2_start AND e.charttime <= c.window2_end 
              AND (LOWER(e.medication) LIKE '%lisinopril%' OR
                   LOWER(e.medication) LIKE '%enalapril%' OR
                   LOWER(e.medication) LIKE '%ramipril%' OR
                   LOWER(e.medication) LIKE '%benazepril%' OR
                   LOWER(e.medication) LIKE '%captopril%' OR
                   LOWER(e.medication) LIKE '%fosinopril%' OR
                   LOWER(e.medication) LIKE '%moexipril%' OR
                   LOWER(e.medication) LIKE '%perindopril%' OR
                   LOWER(e.medication) LIKE '%quinapril%' OR
                   LOWER(e.medication) LIKE '%trandolapril%' OR
                   LOWER(e.medication) LIKE '%losartan%' OR
                   LOWER(e.medication) LIKE '%valsartan%' OR
                   LOWER(e.medication) LIKE '%irbesartan%' OR
                   LOWER(e.medication) LIKE '%candesartan%' OR
                   LOWER(e.medication) LIKE '%telmisartan%' OR
                   LOWER(e.medication) LIKE '%olmesartan%' OR
                   LOWER(e.medication) LIKE '%eprosartan%' OR
                   LOWER(e.medication) LIKE '%sacubitril%' OR
                   LOWER(e.medication) LIKE '%entresto%')
             THEN 1 ELSE 0 END) AS ace_arni_window2,
    -- Loop Diuretic
    MAX(CASE WHEN e.charttime >= c.window1_start AND e.charttime <= c.window1_end 
              AND (LOWER(e.medication) LIKE '%furosemide%' OR
                   LOWER(e.medication) LIKE '%lasix%' OR
                   LOWER(e.medication) LIKE '%bumetanide%' OR
                   LOWER(e.medication) LIKE '%torsemide%' OR
                   LOWER(e.medication) LIKE '%demadex%' OR
                   LOWER(e.medication) LIKE '%ethacrynic acid%')
             THEN 1 ELSE 0 END) AS loop_diuretic_window1,
    MAX(CASE WHEN e.charttime >= c.window2_start AND e.charttime <= c.window2_end 
              AND (LOWER(e.medication) LIKE '%furosemide%' OR
                   LOWER(e.medication) LIKE '%lasix%' OR
                   LOWER(e.medication) LIKE '%bumetanide%' OR
                   LOWER(e.medication) LIKE '%torsemide%' OR
                   LOWER(e.medication) LIKE '%demadex%' OR
                   LOWER(e.medication) LIKE '%ethacrynic acid%')
             THEN 1 ELSE 0 END) AS loop_diuretic_window2
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  'Antidiabetic' AS category,
  (SUM(antidiabetic_window1) * 100.0 / COUNT(*)) AS percent_first_24h,
  (SUM(antidiabetic_window2) * 100.0 / COUNT(*)) AS percent_final_48h,
  SUM(CASE WHEN antidiabetic_window1 = 1 AND antidiabetic_window2 = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN antidiabetic_window1 = 0 AND antidiabetic_window2 = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN antidiabetic_window1 = 1 AND antidiabetic_window2 = 0 THEN 1 ELSE 0 END) AS discontinued
FROM med_flags
UNION ALL
SELECT 
  'Beta-Blocker' AS category,
  (SUM(beta_blocker_window1) * 100.0 / COUNT(*)) AS percent_first_24h,
  (SUM(beta_blocker_window2) * 100.0 / COUNT(*)) AS percent_final_48h,
  SUM(CASE WHEN beta_blocker_window1 = 1 AND beta_blocker_window2 = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN beta_blocker_window1 = 0 AND beta_blocker_window2 = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN beta_blocker_window1 = 1 AND beta_blocker_window2 = 0 THEN 1 ELSE 0 END) AS discontinued
FROM med_flags
UNION ALL
SELECT 
  'ACEi/ARB/ARNI' AS category,
  (SUM(ace_arni_window1) * 100.0 / COUNT(*)) AS percent_first_24h,
  (SUM(ace_arni_window2) * 100.0 / COUNT(*)) AS percent_final_48h,
  SUM(CASE WHEN ace_arni_window1 = 1 AND ace_arni_window2 = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN ace_arni_window1 = 0 AND ace_arni_window2 = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN ace_arni_window1 = 1 AND ace_arni_window2 = 0 THEN 1 ELSE 0 END) AS discontinued
FROM med_flags
UNION ALL
SELECT 
  'Loop Diuretic' AS category,
  (SUM(loop_diuretic_window1) * 100.0 / COUNT(*)) AS percent_first_24h,
  (SUM(loop_diuretic_window2) * 100.0 / COUNT(*)) AS percent_final_48h,
  SUM(CASE WHEN loop_diuretic_window1 = 1 AND loop_diuretic_window2 = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN loop_diuretic_window1 = 0 AND loop_diuretic_window2 = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN loop_diuretic_window1 = 1 AND loop_diuretic_window2 = 0 THEN 1 ELSE 0 END) AS discontinued
FROM med_flags;
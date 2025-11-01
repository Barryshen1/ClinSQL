WITH eligible_admissions AS (
  -- Filter patients: females aged 53-63
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

ugi_bleed_adms AS (
  -- Filter to admissions with primary UGI bleed diagnosis (ICD-10)
  SELECT 
    ea.*
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ea.subject_id = d.subject_id AND ea.hadm_id = d.hadm_id
  WHERE d.icd_version = '10'
    AND d.seq_num = 1  -- Primary diagnosis
    AND (d.icd_code LIKE 'K25%'  -- Gastric ulcer
      OR d.icd_code LIKE 'K26%'  -- Duodenal ulcer
      OR d.icd_code = 'K92.2')   -- GI bleeding
),

procedure_counts AS (
  -- Count distinct diagnostic procedure ICD codes per admission
  SELECT 
    ub.hadm_id,
    ub.los_days,
    CASE 
      WHEN ub.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN ub.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_bucket,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM ugi_bleed_adms ub
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON ub.subject_id = p.subject_id AND ub.hadm_id = p.hadm_id
  WHERE p.icd_version = '10'
    AND p.icd_code IN (
      -- Common ICD-10 diagnostic procedures for UGI bleeding (e.g., endoscopy, biopsy)
      '0DJ08ZZ',  -- Inspection of upper GI, via natural opening, endoscopic
      '0DJD8ZZ',  -- Inspection of upper GI, via natural opening with percutaneous endoscopic assistance
      '0W3G0ZZ',  -- Control bleeding in GI, open approach (diagnostic component)
      '0W3P0ZZ',  -- Control bleeding in GI, percutaneous approach
      '07D50ZZ',  -- Dilation of upper GI, open
      '07D54ZZ',  -- Dilation of upper GI, percutaneous endoscopic
      '0DB68ZX',  -- Excision of stomach, via natural opening endoscopic, diagnostic
      '0D768ZX',  -- Dilation of duodenum, via natural opening endoscopic, diagnostic
      '0WBC8ZZ',  -- Biopsy of peritoneum, via natural opening endoscopic
      '0DB98ZX',  -- Excision of esophagus, via natural opening endoscopic, diagnostic
      '0DJ98ZZ',  -- Inspection of esophagus, via natural opening endoscopic
      '0D798ZX',  -- Dilation of esophagus, via natural opening endoscopic, diagnostic
      '0W3G8ZZ',  -- Control bleeding in upper GI, via natural opening endoscopic
      '0W3H8ZZ'   -- Control bleeding in upper GI, via natural opening with percutaneous endoscopic assistance
    )
  GROUP BY ub.hadm_id, ub.los_days, los_bucket
)

-- Compute percentiles per LOS bucket
SELECT 
  los_bucket,
  q[OFFSET(1)] AS p25,
  q[OFFSET(2)] AS p50,
  q[OFFSET(3)] AS p75
FROM (
  SELECT 
    los_bucket,
    APPROX_QUANTILES(procedure_count, 4) AS q
  FROM procedure_counts
  GROUP BY los_bucket
)
ORDER BY 
  CASE los_bucket 
    WHEN '1-4 days' THEN 1 
    WHEN '5-8 days' THEN 2 
  END;